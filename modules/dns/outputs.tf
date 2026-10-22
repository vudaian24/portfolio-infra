output "acm_validation_fqdns" {
  description = "FQDNs of the ACM validation records, for aws_acm_certificate_validation."
  value       = [for record in cloudflare_dns_record.acm_validation : record.name]
}

output "test_hostname_enabled" {
  description = "True when the test CNAME exists (alb_ready)."
  value       = var.alb_ready
}

output "zone_id" {
  description = "ID of the Cloudflare zone."
  value       = data.cloudflare_zone.main.zone_id
}
