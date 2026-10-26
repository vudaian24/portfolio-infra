# dns

Cloudflare records for the zone `anvd.io.vn` (provider `cloudflare/cloudflare` v5, not Route 53). Design: workspace `docs/architecture/aws-eks.md` (DNS, Edge), workspace `docs/runbooks/dns-cutover.md`.

## What it creates

| Resource | When | Notes |
| --- | --- | --- |
| `data.cloudflare_zone.main` | always | Looked up with `filter = { name = zone_name }`. Token from `CLOUDFLARE_API_TOKEN` in the environment. |
| `cloudflare_dns_record.acm_validation[*]` | always | ACM DNS validation CNAMEs, **not proxied**. Keyed by domain name, so each name gets one record. |
| `cloudflare_dns_record.production[0]` (`portfolio`) | `cutover = true` only | CNAME to the ALB, proxied. Created at cutover, see below. |
| `cloudflare_ruleset.contact_rate_limit` | always | One zone rule in phase `http_ratelimit`: `POST /web-api/contact` on the production host, counted per `ip.src` over 10 s, block for 10 s after 5 requests. This is the Free plan limit (one rule, 10 s period). |

The ALB itself is created by the AWS Load Balancer Controller from the Ingress, named `portfolio-prod-web`. The caller looks it up with `data "aws_lb"` and passes `alb_dns_name`. Only when `alb_ready` is true, so the lookup does not fail before the ALB exists.

## Order for a new stack

1. **First apply:** `alb_ready = false`, `cutover = false`. Creates the ACM validation records and the rate limit rule.
2. **ALB records:** after Argo CD created the Ingress and the ALB exists, set `alb_ready = true` in `terraform.tfvars` and apply.
3. **Cutover:** see below.

## Cutover: the production record

No `portfolio` record may point at Vercel while ACM issues the certificate (see [Vercel CAA and ACM](#vercel-caa-and-acm)). With no `portfolio` record in the zone, the cutover (one commit to `main`) only sets `cutover = true` in `terraform.tfvars`. The plan must show one new `production[0]` record, a proxied CNAME to the ALB, and nothing else.

If a `portfolio` record exists again at cutover, for example after a rollback to Vercel, adopt it in the same change instead of creating a second one:

1. Read the zone ID and the record ID from the Cloudflare dashboard (or the API with the zone-scoped token). Do not paste them into chats or tickets. The import ID is `<zone_id>/<dns_record_id>`.
2. Add `envs/prod/imports.tf`:

   ```hcl
   import {
     to = module.dns.cloudflare_dns_record.production[0]
     id = "<zone_id>/<dns_record_id>"
   }
   ```

3. Set `cutover = true` in `terraform.tfvars`. The plan must show one import and one update of `content` (and of `proxied`, if the record was DNS only like the Vercel one), nothing else.
4. After the import, delete `imports.tf` in the same or the next commit.

Rollback: there is none off AWS. `content` is `var.alb_dns_name` and the module has no second target, so a failure is fixed inside AWS (workspace `docs/runbooks/rollback.md`). Setting `cutover = false` is not a rollback either: Terraform would delete the record and the name would stop resolving.

## Vercel CAA and ACM

While `portfolio` is a CNAME to Vercel, a CAA lookup for `portfolio.anvd.io.vn` follows the CNAME and returns Vercel's CAA set (`letsencrypt.org`, `pki.goog`, `globalsign.com`, `sectigo.com`). Amazon is not in it, so ACM fails that name with `CAA_ERROR`. A CAA record cannot sit next to the CNAME, and one on `anvd.io.vn` does not help, because the lookup stops at Vercel's set. A failed certificate is not retried.

To recover a certificate that failed this way, delete the record, then replace the certificate with `terraform apply -replace=aws_acm_certificate.web`. Request or replace the certificate only while `portfolio` does not point at Vercel. An issued certificate is not affected by a later rollback to Vercel; ACM checks CAA again only at renewal, which falls after the AWS run.

## Manual checks outside Terraform (must pass before `alb_ready`)

These are zone-wide settings. They affect every host in `anvd.io.vn`, including Vercel after a rollback, so Terraform does not manage them (the design only scopes them to the portfolio hosts):

- **SSL/TLS mode for `portfolio`: Full (strict).** The ALB only speaks HTTPS on 443 with a public certificate. Flexible or Full would fail or send traffic over HTTP. Use a Configuration Rule scoped to the hostname, as workspace `docs/runbooks/cluster-operations.md#bootstrap-argo-cd-new-cluster-only` step 7 says, rather than the zone setting.
- **Always Use HTTPS:** check it is what you want for the zone. Changing it affects every host in the zone.

## Notes

- Every record that points at the ALB is proxied. A DNS-only record would expose the ALB name to direct traffic (aws-eks.md, Origin exposure).
- The ACM validation records must stay DNS only.
- Import ID formats and the v5 attribute names were checked against the provider schema (`providers schema -json`) and [the cloudflare_dns_record docs](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record).
