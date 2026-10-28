output "access_aud_tags" {
  description = "Access application audience (AUD) tags, keyed by app, for an origin that checks the Access JWT. Not secret."
  value       = { for key, app in cloudflare_zero_trust_access_application.app : key => app.aud }
}

output "team_domain" {
  description = "Zero Trust team domain. Access certificates for JWT checks: https://<team_domain>/cdn-cgi/access/certs."
  value       = "${var.team_name}.cloudflareaccess.com"
}

output "tunnel_id" {
  description = "ID of the Cloudflare Tunnel. Its token is read in the dashboard, not here."
  value       = cloudflare_zero_trust_tunnel_cloudflared.admin.id
}
