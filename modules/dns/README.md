# dns

Cloudflare records for the zone `anvd.io.vn` (provider `cloudflare/cloudflare` v5, not Route 53). Design: [aws-eks.md](../../../docs/architecture/aws-eks.md) (DNS, Edge), [dns-cutover.md](../../../docs/runbooks/dns-cutover.md).

## What it creates

| Resource | When | Notes |
| --- | --- | --- |
| `data.cloudflare_zone.main` | always | Looked up with `filter = { name = zone_name }`. Token from `CLOUDFLARE_API_TOKEN` in the environment. |
| `cloudflare_dns_record.acm_validation[*]` | always | ACM DNS validation CNAMEs, **not proxied**. Keyed by domain name, so each name gets one record. |
| `cloudflare_dns_record.test[0]` (`portfolio-aws`) | `alb_ready = true` | CNAME to the ALB DNS name, **proxied**. |
| `cloudflare_dns_record.production[0]` (`portfolio`) | `cutover = true` only | CNAME to the ALB, proxied. Never created while the record is the Vercel one, see below. |
| `cloudflare_ruleset.contact_rate_limit` | always | One zone rule in phase `http_ratelimit`: `POST /web-api/contact` on the two portfolio hosts, counted per `ip.src` over 10 s, block for 10 s after 5 requests. This is the Free plan limit (one rule, 10 s period). |

The ALB itself is created by the AWS Load Balancer Controller from the Ingress, named `portfolio-prod-web`. The caller looks it up with `data "aws_lb"` and passes `alb_dns_name`. Only when `alb_ready` is true, so the lookup does not fail before the ALB exists.

## Phase steps (Terraform side)

1. **Phase 2:** apply with `alb_ready = false`, `cutover = false`. Creates the ACM validation records and the rate limit rule.
2. **Phase 3:** after Argo CD created the Ingress and the ALB exists, set `alb_ready = true` in `terraform.tfvars` and apply. Creates `portfolio-aws`.
3. **Phase 4:** see the cutover below.

## Cutover: the production record (not managed before Phase 4)

`portfolio` points at Vercel today. Terraform does not manage it until Phase 4, so the first apply cannot create a second record. In the Phase 4 change (one commit to `main`):

1. Read the zone ID and the record ID from the Cloudflare dashboard (or the API with the zone-scoped token). Do not paste them into chats or tickets. The import ID is `<zone_id>/<dns_record_id>`.
2. Add `envs/prod/imports.tf` (not committed before Phase 4):

   ```hcl
   import {
     to = module.dns.cloudflare_dns_record.production[0]
     id = "<zone_id>/<dns_record_id>"
   }
   ```

3. Set `cutover = true` in `terraform.tfvars`. The plan must show one import and one update of `content`, nothing else. The record stays proxied.
4. After the import, delete `imports.tf` in the same or the next commit.

Rollback: follow [dns-cutover.md](../../../docs/runbooks/dns-cutover.md#rollback), which points the record back at the Vercel target. Setting `cutover = false` alone would make Terraform try to delete the record.

## Manual checks outside Terraform (must pass before `alb_ready`)

These are zone-wide settings. They affect every host in `anvd.io.vn`, including the live Vercel site, so Terraform does not manage them (the design only scopes them to the portfolio hosts):

- **SSL/TLS mode for `portfolio-aws` (and later `portfolio`): Full (strict).** The ALB only speaks HTTPS on 443 with a public certificate. Flexible or Full would fail or send traffic over HTTP. Use a Configuration Rule scoped to the two hostnames, as [dns-cutover.md](../../../docs/runbooks/dns-cutover.md) step 4 says, rather than the zone setting.
- **Always Use HTTPS:** check it is what you want for the zone. Changing it affects Vercel too.

## Notes

- Every record that points at the ALB is proxied. A DNS-only record would expose the ALB name to direct traffic (aws-eks.md, Origin exposure).
- The ACM validation records must stay DNS only.
- Import ID formats and the v5 attribute names were checked against the provider schema (`providers schema -json`) and [the cloudflare_dns_record docs](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record).
