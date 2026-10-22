# Public certificate for the ALB, found by the Load Balancer Controller through its host names.
# DNS validation: the records are created by module.dns (Cloudflare, DNS only).
resource "aws_acm_certificate" "web" {
  domain_name               = var.production_hostname
  subject_alternative_names = [var.test_hostname]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "web" {
  certificate_arn         = aws_acm_certificate.web.arn
  validation_record_fqdns = module.dns.acm_validation_fqdns
}
