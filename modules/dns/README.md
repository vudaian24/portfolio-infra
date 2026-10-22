# dns

Planned: Cloudflare records for the zone `anvd.io.vn`, using the Cloudflare provider (not Route 53).

- `portfolio`: CNAME to the ALB DNS name, proxied. The ALB is looked up by its fixed name `portfolio-prod-web`, so this record can only be applied after Argo CD has created the Ingress. The current CNAME to Vercel is imported first, then retargeted at cutover.
- `portfolio-aws`: test hostname, CNAME to the ALB, proxied. Removed after cutover.
- ACM validation records for the certificate, DNS only.
- One rate limiting rule for `POST /web-api/contact`.

Every record that points at the ALB must stay proxied.

Stub today: only `terraform.tf` has content. Not called from `envs/prod` yet. The target design is in the parent workspace `docs/`.
