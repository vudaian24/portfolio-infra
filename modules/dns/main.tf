# Cloudflare token: CLOUDFLARE_API_TOKEN in the environment, never in a file. Scoped to the zone.
data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}

# ACM validation. DNS only: a proxied validation record would not reach ACM.
resource "cloudflare_dns_record" "acm_validation" {
  for_each = var.acm_validation_records

  zone_id = data.cloudflare_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.value
  ttl     = 1
  proxied = false
  comment = "ACM DNS validation (managed by Terraform)"
}

# The ALB admits Cloudflare only, so the record stays proxied (aws-eks.md, Origin exposure).
resource "cloudflare_dns_record" "test" {
  count = var.alb_ready ? 1 : 0

  zone_id = data.cloudflare_zone.main.zone_id
  name    = var.test_hostname
  type    = "CNAME"
  content = var.alb_dns_name
  ttl     = 1
  proxied = true
  comment = "Test hostname for the EKS stack; removed after cutover (managed by Terraform)"

  lifecycle {
    precondition {
      condition     = var.alb_dns_name != null
      error_message = "alb_dns_name must be set when alb_ready is true."
    }
  }
}

# Phase 4 only. Adopt the existing Vercel record first (import in docs/runbooks/dns-cutover.md).
resource "cloudflare_dns_record" "production" {
  count = var.cutover ? 1 : 0

  zone_id = data.cloudflare_zone.main.zone_id
  name    = var.production_hostname
  type    = "CNAME"
  content = var.alb_dns_name
  ttl     = 1
  proxied = true
  comment = "Production hostname on the EKS stack (managed by Terraform)"

  lifecycle {
    precondition {
      condition     = var.alb_dns_name != null
      error_message = "alb_dns_name must be set when cutover is true."
    }
  }
}

# One rate limiting rule (Free plan). Scoped to the two portfolio hosts so it does not
# touch other hosts in the zone. Counts requests per client IP over 10 s.
resource "cloudflare_ruleset" "contact_rate_limit" {
  zone_id     = data.cloudflare_zone.main.zone_id
  name        = "portfolio contact form rate limit"
  description = "Blocks clients that POST the contact form too often (managed by Terraform)"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      action      = "block"
      enabled     = true
      description = "Contact form POST rate limit"
      expression = format(
        "(http.host eq \"%s\" or http.host eq \"%s\") and http.request.method eq \"POST\" and http.request.uri.path eq \"%s\"",
        var.production_hostname,
        var.test_hostname,
        var.contact_rate_limit.path,
      )

      ratelimit = {
        characteristics     = ["ip.src", "cf.colo.id"]
        period              = 10
        requests_per_period = var.contact_rate_limit.requests_per_period
        mitigation_timeout  = var.contact_rate_limit.mitigation_timeout
      }
    },
  ]
}
