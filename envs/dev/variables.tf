variable "aws_account_id" {
  description = "AWS account ID allowed to be applied for this environment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name, used as the resource name prefix."
  type        = string
  default     = "portfolio"
}

variable "region" {
  description = "AWS region to deploy the infrastructure to."
  type        = string
  default     = "ap-southeast-1"
}
