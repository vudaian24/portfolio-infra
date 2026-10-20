variable "noncurrent_version_retention_days" {
  description = "Number of days to keep noncurrent state file versions before expiring them."
  type        = number
  default     = 90
}

variable "project" {
  description = "Project name, used as the resource name prefix."
  type        = string
  default     = "my-portfolio"
}

variable "region" {
  description = "AWS region of the state bucket."
  type        = string
  default     = "ap-southeast-1"
}
