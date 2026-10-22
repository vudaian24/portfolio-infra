variable "aws_account_id" {
  description = "AWS account ID allowed to be applied for this environment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits."
  }
}

variable "environment" {
  description = "Environment name. The only environment is prod (ADR 0004)."
  type        = string
  default     = "prod"

  validation {
    condition     = var.environment == "prod"
    error_message = "environment must be prod."
  }
}

variable "github_environment" {
  description = "GitHub environment of portfolio-web whose jobs may assume the web CI role."
  type        = string
  default     = "aws-production"
}

variable "github_oidc_subject_prefix" {
  description = "OIDC subject prefix of portfolio-web (immutable format with owner and repository IDs). Read it with: gh api repos/vudaian24/portfolio-web/actions/oidc/customization/sub --jq .sub_claim_prefix"
  type        = string
  default     = "repo:vudaian24@90129616/portfolio-web@1054987424"

  validation {
    condition     = can(regex("^repo:[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$", var.github_oidc_subject_prefix))
    error_message = "github_oidc_subject_prefix must look like repo:OWNER@OWNER_ID/REPO@REPO_ID."
  }
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
