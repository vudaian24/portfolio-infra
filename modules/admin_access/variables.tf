variable "account_id" {
  description = "Cloudflare account ID that owns the zone, the tunnel and the Zero Trust organization."
  type        = string
}

variable "allowed_emails" {
  description = "Email addresses that may log in to the admin apps (owner and viewers). Personal data: set from a secret, never committed."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.allowed_emails) > 0 && alltrue([for email in var.allowed_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", email))])
    error_message = "allowed_emails must hold at least one email address."
  }
}

variable "apps" {
  description = "Admin apps keyed by short name: the public hostname and the in-cluster service that cloudflared forwards to."
  type = map(object({
    hostname = string
    service  = string
  }))

  validation {
    condition     = alltrue([for app in var.apps : can(regex("^http://[a-z0-9.-]+(:[0-9]+)?$", app.service))])
    error_message = "Each service must be an in-cluster http:// URL; TLS ends at the Cloudflare edge."
  }
}

variable "name" {
  description = "Name of the tunnel and prefix of the Access apps and policy, e.g. portfolio-prod-admin."
  type        = string
}

variable "session_duration" {
  description = "How long an Access login stays valid."
  type        = string
  default     = "8h"
}

variable "team_name" {
  description = "Zero Trust team name: the <team> in <team>.cloudflareaccess.com. Created by hand with the organization."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.team_name))
    error_message = "team_name must be the bare team name, without .cloudflareaccess.com."
  }
}

variable "zone_id" {
  description = "ID of the Cloudflare zone that holds the admin hostnames."
  type        = string
}
