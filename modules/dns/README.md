# dns

Planned: Cloudflare records for the zone `anvd.io.vn`, using the Cloudflare provider (not Route 53).

- `portfolio`: A record to the Elastic IP, proxied. The current CNAME to Vercel is imported first, then changed at cutover.
- `portfolio-aws`: test hostname, A record to the Elastic IP, proxied. Removed after cutover.
- One rate limiting rule for `POST /web-api/contact`.

Every record that points at the Elastic IP must stay proxied, or the origin IP leaks.

Stub today: only `terraform.tf` has content. The target design is in the parent workspace `docs/`.
