variable "aws_account_id" {
  description = "AWS account ID allowed to be applied for this directory."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits."
  }
}

variable "noncurrent_version_retention_days" {
  description = "Number of days to keep noncurrent state file versions before expiring them."
  type        = number
  default     = 90
}

variable "project" {
  description = "Project name, used as the resource name prefix."
  type        = string
  default     = "portfolio"
}

variable "region" {
  description = "AWS region of the state bucket."
  type        = string
  default     = "ap-southeast-1"
}
