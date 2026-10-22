variable "app_port" {
  description = "TCP port of the app pods. The ALB forwards to it inside the VPC."
  type        = number
  default     = 3000

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535
    error_message = "app_port must be a valid TCP port."
  }
}

# Source: https://www.cloudflare.com/ips-v4 (fetched 2026-10-22). Update when Cloudflare changes it.
variable "cloudflare_ipv4_cidrs" {
  description = "Cloudflare IPv4 ranges allowed to reach the ALB on TCP 443."
  type        = list(string)
  default = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]

  validation {
    condition     = length(var.cloudflare_ipv4_cidrs) > 0 && alltrue([for c in var.cloudflare_ipv4_cidrs : can(cidrhost(c, 0)) && !can(regex(":", c))])
    error_message = "cloudflare_ipv4_cidrs must be a non-empty list of IPv4 CIDR blocks."
  }
}

variable "name_prefix" {
  description = "Resource name prefix, e.g. portfolio-prod."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Public subnets are carved out of it with /24 blocks."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && tonumber(split("/", var.vpc_cidr)[1]) <= 16
    error_message = "vpc_cidr must be an IPv4 CIDR block with a prefix length of /16 or shorter."
  }
}
