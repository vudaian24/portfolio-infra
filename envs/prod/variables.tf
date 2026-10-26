variable "access_allowed_emails" {
  description = "Emails that may log in to Argo CD and Grafana through Cloudflare Access (owner and viewers). Personal data: set in account.auto.tfvars and the TF_ACCESS_ALLOWED_EMAILS secret, never committed. Used only when admin_access_enabled is true."
  type        = list(string)
  sensitive   = true
  default     = []

  validation {
    condition     = !var.admin_access_enabled || length(var.access_allowed_emails) > 0
    error_message = "access_allowed_emails must not be empty when admin_access_enabled is true."
  }
}

variable "access_team_name" {
  description = "Zero Trust team name (<team>.cloudflareaccess.com), created by hand with the organization. Required when admin_access_enabled is true."
  type        = string
  default     = null

  validation {
    condition     = !var.admin_access_enabled || var.access_team_name != null
    error_message = "access_team_name must be set when admin_access_enabled is true."
  }
}

variable "admin_access_enabled" {
  description = "Publish Argo CD and Grafana through Cloudflare Access and a Tunnel (ADR 0009, modules/admin_access). Set in terraform.tfvars."
  type        = bool
  default     = false
}

variable "admin_cidrs" {
  description = "IPv4 CIDR blocks of the admins that may reach the public EKS API when public_endpoint is true (break-glass). May be []. Set in account.auto.tfvars (never committed)."
  type        = list(string)
}

variable "admin_principal_arn" {
  description = "IAM role or user ARN of the admin with cluster admin access. Set in account.auto.tfvars (never committed)."
  type        = string
}

variable "alb_ready" {
  description = "True once the ALB exists (the controller creates it from the Ingress), so its DNS name can be read."
  type        = bool
  default     = false
}

variable "argocd_hostname" {
  description = "Hostname of the Argo CD UI behind Cloudflare Access."
  type        = string
  default     = "argocd.anvd.io.vn"
}

variable "aws_account_id" {
  description = "AWS account ID allowed to be applied for this environment."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits."
  }
}

variable "budget_email" {
  description = "Email address for AWS Budgets alerts. Set in account.auto.tfvars (never committed)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_email))
    error_message = "budget_email must be an email address."
  }
}

variable "cluster_deletion_protection" {
  description = "EKS deletion protection. Set to false in a commit before the decommission destroy (docs/runbooks/decommission.md)."
  type        = bool
  default     = true
}

variable "cluster_version" {
  description = "Kubernetes version of the EKS cluster (ADR 0003)."
  type        = string
  default     = "1.36"
}

variable "cutover" {
  description = "Point the production hostname at the ALB. See docs/runbooks/dns-cutover.md."
  type        = bool
  default     = false
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

variable "github_terraform_subject_prefix" {
  description = "OIDC subject prefix of portfolio-infra (ADR 0008). Read it with: gh api repos/vudaian24/portfolio-infra/actions/oidc/customization/sub --jq .sub_claim_prefix"
  type        = string
  default     = "repo:vudaian24@90129616/portfolio-infra@1427185252"

  validation {
    condition     = can(regex("^repo:[A-Za-z0-9_.-]+@[0-9]+/[A-Za-z0-9_.-]+@[0-9]+$", var.github_terraform_subject_prefix))
    error_message = "github_terraform_subject_prefix must look like repo:OWNER@OWNER_ID/REPO@REPO_ID."
  }
}

variable "github_terraform_environment" {
  description = "GitHub environment of portfolio-infra whose apply job may assume the Terraform apply role."
  type        = string
  default     = "production"
}

variable "grafana_hostname" {
  description = "Hostname of the Grafana UI behind Cloudflare Access."
  type        = string
  default     = "grafana.anvd.io.vn"
}

variable "night_shutdown_enabled" {
  description = "Create the scheduled night shutdown of the node group (ADR 0011, modules/night_scheduler). Creating it does not start it: the SSM flag it creates holds \"false\". Set in terraform.tfvars."
  type        = bool
  default     = false
}

variable "night_shutdown_end" {
  description = "Local time the node group goes back to 1, HH:MM in Asia/Ho_Chi_Minh. Earlier than the hour the site must answer: a node needs 5 to 7 minutes."
  type        = string
  default     = "06:45"
}

variable "night_shutdown_start" {
  description = "Local time the node group goes to 0, HH:MM in Asia/Ho_Chi_Minh. The site returns 503 from then until night_shutdown_end."
  type        = string
  default     = "23:00"
}

variable "node_release_version" {
  description = "AL2023 AMI release version of the node group, pinned in terraform.tfvars. null lets EKS choose at creation."
  type        = string
  default     = null
}

variable "production_hostname" {
  description = "Production hostname, served by the ALB."
  type        = string
  default     = "portfolio.anvd.io.vn"
}

variable "project" {
  description = "Project name, used as the resource name prefix."
  type        = string
  default     = "portfolio"
}

variable "public_endpoint" {
  description = "Break-glass switch: true turns on the public EKS API endpoint for admin_cidrs. Admins normally use the Session Manager tunnel (scripts/eks-tunnel.sh). Set in terraform.tfvars."
  type        = bool
  default     = false
}

variable "region" {
  description = "AWS region to deploy the infrastructure to."
  type        = string
  default     = "ap-southeast-1"
}

variable "tfstate_bucket_name" {
  description = "Name of the state bucket from bootstrap (terraform -chdir=bootstrap output -raw state_bucket_name). Set in account.auto.tfvars (never committed)."
  type        = string

  validation {
    condition     = can(regex("^portfolio-tfstate-[0-9]{12}$", var.tfstate_bucket_name))
    error_message = "tfstate_bucket_name must look like portfolio-tfstate-<12-digit account ID>."
  }
}

variable "test_hostname" {
  description = "Second name on the ACM certificate, with no DNS record. Removing it replaces the certificate, which cannot be deleted while the ALB listener uses it."
  type        = string
  default     = "portfolio-aws.anvd.io.vn"
}
