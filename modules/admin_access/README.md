# admin_access

Argo CD and Grafana through Cloudflare Access and a Cloudflare Tunnel (provider `cloudflare/cloudflare` v5). Design: ADR 0009 (workspace `docs/adr/0009-hybrid-edge-with-cloudflare-tunnel-for-admin-uis.md`), workspace `docs/architecture/edge-access.png`. The site keeps the ALB; this module does not touch it.

## What it creates

| Resource | Notes |
| --- | --- |
| `cloudflare_zero_trust_access_identity_provider.otp` | One-time PIN by email, the only login method of the apps. Viewers need no identity provider account. |
| `cloudflare_zero_trust_access_policy.allowed_emails` | Reusable allow policy: the `allowed_emails` list, session `session_duration` (8 h). |
| `cloudflare_zero_trust_access_application.app[*]` | One self-hosted app per entry in `apps`, using the policy above. Its `aud` tag goes to the tunnel config and to Grafana `auth.jwt`. |
| `cloudflare_zero_trust_tunnel_cloudflared.admin` | Remotely managed tunnel (`config_src = "cloudflare"`), no `tunnel_secret` in Terraform. |
| `cloudflare_zero_trust_tunnel_cloudflared_config.admin` | One ingress rule per app to its ClusterIP service, each with `access.required` and the app's AUD tag, then a catch-all `http_status:404`. |
| `cloudflare_dns_record.app[*]` | Proxied CNAME per hostname to `<tunnel-id>.cfargotunnel.com`. |

## Before the first apply

- The Zero Trust organization exists, created by hand. `team_name` is its team name (`<team>.cloudflareaccess.com`).
- No One-time PIN login method exists in the organization yet. If one was added by hand, import it into `cloudflare_zero_trust_access_identity_provider.otp` instead of creating a second one.
- The Cloudflare API token used for the apply (`CLOUDFLARE_API_TOKEN` on the laptop) has, besides the zone permissions: Account, Cloudflare Tunnel: Edit; Access: Apps and Policies: Edit; Access: Organizations, Identity Providers, and Groups: Edit.

## After the apply

1. Read the tunnel token in the Zero Trust dashboard (Networks, Tunnels, the tunnel, install connector) and store it with the AWS CLI as `/portfolio/prod/cloudflare-tunnel-token` (workspace `docs/runbooks/secrets.md`). Never paste it into a chat, a ticket or a file.
2. Deploy `cloudflared` from `portfolio-gitops`. Until it runs, the hostnames show the Access login and then Cloudflare error 1033.

`allowed_emails` is personal data. It comes from `account.auto.tfvars` on the laptop, and the variable is sensitive, so plans do not print it.
