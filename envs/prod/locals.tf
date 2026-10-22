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
}
