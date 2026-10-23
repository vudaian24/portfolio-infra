variable "acm_validation_records" {
  description = "DNS validation records of the ACM certificate, keyed by domain name. Created DNS only (not proxied)."
  type = map(object({
    name  = string
    type  = string
    value = string
  }))
}

variable "alb_dns_name" {
  description = "DNS name of the ALB portfolio-prod-web (from data aws_lb in the caller). Required when alb_ready is true."
  type        = string
  default     = null
}

variable "alb_ready" {
  description = "True once the ALB exists (the controller creates it from the Ingress). Required by cutover."
  type        = bool
  default     = false
}

variable "contact_rate_limit" {
  description = "Rate limit for the contact form on the production host (Free plan: one rule, period 10 s, block)."
  type = object({
    path                = string
    requests_per_period = number
    mitigation_timeout  = number
  })
  default = {
    path                = "/web-api/contact"
    requests_per_period = 5
    mitigation_timeout  = 10
  }
}

variable "cutover" {
  description = "Create the production hostname record pointing at the ALB (docs/runbooks/dns-cutover.md)."
  type        = bool
  default     = false

  validation {
    condition     = !var.cutover || var.alb_ready
    error_message = "cutover requires alb_ready = true."
  }
}

variable "production_hostname" {
  description = "Production hostname, a record inside zone_name."
  type        = string
  default     = "portfolio.anvd.io.vn"
}

variable "zone_name" {
  description = "Cloudflare zone that holds the records."
  type        = string
  default     = "anvd.io.vn"
}
