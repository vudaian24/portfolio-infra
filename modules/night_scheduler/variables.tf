variable "alert_email" {
  description = "Address that receives the SNS alarm mail. Personal data: set from account.auto.tfvars or a CI secret, never committed."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be an email address."
  }
}

variable "cluster_name" {
  description = "Name of the EKS cluster that owns the node group."
  type        = string
}

variable "flag_parameter_name" {
  description = "SSM parameter that switches the loop on, e.g. /portfolio/prod/night-shutdown-enabled. Created here with \"false\"; flip it with the AWS CLI."
  type        = string

  validation {
    condition     = can(regex("^/[a-z0-9/-]+[a-z0-9]$", var.flag_parameter_name))
    error_message = "flag_parameter_name must start with / and contain only lowercase letters, digits, hyphens and slashes."
  }
}

variable "log_retention_days" {
  description = "Retention of the Lambda log group. The stack is destroyed by 2026-12-01, so a week is enough to debug a night."
  type        = number
  default     = 7
}

variable "name_prefix" {
  description = "Resource name prefix, e.g. portfolio-prod."
  type        = string
}

variable "node_group_name" {
  description = "Name of the EKS managed node group to scale."
  type        = string
}

variable "reconcile_interval_minutes" {
  description = "Minutes between runs. Must divide 60 and must divide the minute of shutdown_time and startup_time, or those times are never hit."
  type        = number
  default     = 15

  validation {
    condition     = contains([5, 10, 15, 20, 30], var.reconcile_interval_minutes)
    error_message = "reconcile_interval_minutes must be one of 5, 10, 15, 20, 30."
  }
}

variable "shutdown_time" {
  description = "Local time the node group goes to 0, HH:MM (ADR 0011: 23:00)."
  type        = string
  default     = "23:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.shutdown_time))
    error_message = "shutdown_time must be HH:MM in 24-hour form."
  }
}

variable "site_alarm_name" {
  description = "Alarm whose actions the loop turns off inside the window, because the site is meant to be down then. null leaves alarm actions alone."
  type        = string
  default     = null
}

variable "startup_time" {
  description = "Local time the node group goes back to 1, HH:MM. Earlier than the hour the site must answer, as margin for a slow node join; the measured recovery is 82 seconds (ADR 0011: 06:45 for 07:00)."
  type        = string
  default     = "06:45"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.startup_time))
    error_message = "startup_time must be HH:MM in 24-hour form."
  }
}

variable "timezone" {
  description = "IANA time zone the two times are read in."
  type        = string
  default     = "Asia/Ho_Chi_Minh"
}
