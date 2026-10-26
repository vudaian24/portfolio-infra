variable "admin_cidrs" {
  description = "IPv4 CIDR blocks allowed to reach the public EKS API endpoint when public_endpoint is true (break-glass). May be empty. No default: set in account.auto.tfvars."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.admin_cidrs : can(cidrhost(c, 0)) && !can(regex(":", c))])
    error_message = "admin_cidrs must be a list of IPv4 CIDR blocks."
  }

  validation {
    condition     = !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "admin_cidrs must not contain 0.0.0.0/0; the API endpoint is for the admin allow-list only."
  }
}

variable "admin_principal_arn" {
  description = "IAM role or user ARN that gets cluster admin through an access entry. No default: set in account.auto.tfvars."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role|user)/", var.admin_principal_arn))
    error_message = "admin_principal_arn must be an IAM role or user ARN."
  }
}

variable "cluster_version" {
  description = "Kubernetes version of the EKS control plane and node group (ADR 0003: 1.36, standard support)."
  type        = string
  default     = "1.36"
}

variable "deletion_protection" {
  description = "EKS deletion protection. Turn it off in a commit before the decommission destroy (docs/runbooks/decommission.md)."
  type        = bool
  default     = true
}

variable "external_secrets_service_account" {
  description = "Namespace and service account of External Secrets, as in portfolio-gitops/charts/external-secrets/values.yaml. Keep in sync."
  type = object({
    namespace = string
    name      = string
  })
  default = {
    namespace = "external-secrets"
    name      = "external-secrets"
  }
}

variable "load_balancer_controller_service_account" {
  description = "Namespace and service account of the AWS Load Balancer Controller, as in portfolio-gitops/charts/aws-load-balancer-controller/values.yaml. Keep in sync."
  type = object({
    namespace = string
    name      = string
  })
  default = {
    namespace = "kube-system"
    name      = "aws-load-balancer-controller"
  }
}

variable "name_prefix" {
  description = "Resource name prefix, e.g. portfolio-prod. Also the EKS cluster name."
  type        = string
}

variable "node_instance_type" {
  description = "Instance type of the single managed node (Graviton, arm64)."
  type        = string
  default     = "t4g.medium"
}

variable "node_min_size" {
  description = "Minimum size of the node group. 0 is required for the scheduled night shutdown (ADR 0011); 1 otherwise, so nothing can scale the site to zero by accident."
  type        = number
  default     = 1

  validation {
    condition     = contains([0, 1], var.node_min_size)
    error_message = "node_min_size must be 0 or 1; the group never holds more than one node."
  }
}

variable "node_release_version" {
  description = "EKS AL2023 AMI release version of the node group, for example 1.36.x-YYYYMMDD. null lets EKS pick the recommended release at creation. Set it in terraform.tfvars to pin it; a bump is an apply, see docs/runbooks/cluster-operations.md."
  type        = string
  default     = null
}

variable "node_root_volume_size" {
  description = "Root volume size of the node in GiB (gp3, encrypted)."
  type        = number
  default     = 20

  validation {
    condition     = var.node_root_volume_size >= 20 && var.node_root_volume_size <= 50
    error_message = "node_root_volume_size must be between 20 and 50 GiB."
  }
}

variable "public_endpoint" {
  description = "Turn on the public EKS API endpoint, limited to admin_cidrs. Break-glass only: admins reach the private endpoint through Session Manager (scripts/eks-tunnel.sh)."
  type        = bool
  default     = false
}

variable "public_subnet_ids" {
  description = "IDs of the two public subnets (one per AZ). The node runs in them; EKS requires at least two."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "EKS needs at least two subnets in different AZs."
  }
}

variable "secrets_path_prefix" {
  description = "SSM path prefix External Secrets may read, e.g. /portfolio/prod (docs/runbooks/secrets.md)."
  type        = string

  validation {
    condition     = can(regex("^/[a-z0-9/-]+[a-z0-9]$", var.secrets_path_prefix))
    error_message = "secrets_path_prefix must start with / and contain only lowercase letters, digits, hyphens and slashes."
  }
}
