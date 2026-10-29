# Admin UIs through Cloudflare Access and a Cloudflare Tunnel (ADR 0009). The site keeps the ALB.
# Token: var.cloudflare_api_token of the root provider (envs/prod), with account-level Tunnel and Access permissions.

# One-time PIN by email: viewers need no account at an identity provider.
resource "cloudflare_zero_trust_access_identity_provider" "otp" {
  account_id = var.account_id
  name       = "One-time PIN"
  type       = "onetimepin"
  config     = {}
}

# Reusable policy shared by every admin app: only the listed emails get in.
resource "cloudflare_zero_trust_access_policy" "allowed_emails" {
  account_id       = var.account_id
  name             = "${var.name} allowed emails"
  decision         = "allow"
  session_duration = var.session_duration
  include          = [for email in var.allowed_emails : { email = { email = email } }]
}

resource "cloudflare_zero_trust_access_application" "app" {
  for_each = var.apps

  account_id                 = var.account_id
  name                       = "${var.name} ${each.key}"
  type                       = "self_hosted"
  destinations               = [{ type = "public", uri = each.value.hostname }]
  session_duration           = var.session_duration
  allowed_idps               = [cloudflare_zero_trust_access_identity_provider.otp.id]
  auto_redirect_to_identity  = true
  app_launcher_visible       = false
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "lax"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allowed_emails.id
    precedence = 1
  }]
}

# Remotely managed: cloudflared runs with only the tunnel token, and the routes below live in
# Cloudflare. The token is read in the dashboard and put in SSM by hand, so it never enters state.
resource "cloudflare_zero_trust_tunnel_cloudflared" "admin" {
  account_id = var.account_id
  name       = var.name
  config_src = "cloudflare"
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "admin" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.admin.id

  config = {
    # cloudflared also checks the Access token, so a request that skipped Access stops here too.
    ingress = concat(
      [for key, app in var.apps : {
        hostname = app.hostname
        service  = app.service
        origin_request = {
          access = {
            required  = true
            team_name = var.team_name
            aud_tag   = [cloudflare_zero_trust_access_application.app[key].aud]
          }
        }
      }],
      [{ service = "http_status:404" }],
    )
  }
}

# Proxied, so visitors reach Access first; the target name only resolves inside Cloudflare.
resource "cloudflare_dns_record" "app" {
  for_each = var.apps

  zone_id = var.zone_id
  name    = each.value.hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.admin.id}.cfargotunnel.com"
  ttl     = 1
  proxied = true
  comment = "Admin UI through Cloudflare Tunnel ${var.name} (managed by Terraform)"
}
