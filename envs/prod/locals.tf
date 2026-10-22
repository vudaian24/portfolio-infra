locals {
  # Resource name prefix, e.g. portfolio-prod-vpc
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  ecr_repository_name = "${local.name_prefix}-web"
  web_ci_role_name    = "${local.name_prefix}-web-ci"

  # Names of the Terraform CI roles (ci.tf) and the ALB created by the controller (dns.tf)
  tf_plan_role_name  = "${local.name_prefix}-tf-plan"
  tf_apply_role_name = "${local.name_prefix}-tf-apply"
  alb_name           = "${local.name_prefix}-web"

  # SSM path of the secrets (docs/runbooks/secrets.md)
  secrets_path_prefix = "/${var.project}/${var.environment}"
}
