output "access_aud_tags" {
  description = "Cloudflare Access AUD tags of the admin apps, for Grafana auth.jwt in portfolio-gitops. Empty while admin_access_enabled is false. Not secret."
  value       = try(module.admin_access[0].access_aud_tags, {})
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate for the ALB (portfolio.anvd.io.vn and portfolio-aws.anvd.io.vn)."
  value       = aws_acm_certificate_validation.web.certificate_arn
}

output "alb_security_group_id" {
  description = "ID of the ALB security group portfolio-prod-web (443 from Cloudflare only)."
  value       = module.network.alb_security_group_id
}

output "cloudflare_tunnel_id" {
  description = "ID of the admin Cloudflare Tunnel, null while admin_access_enabled is false."
  value       = try(module.admin_access[0].tunnel_id, null)
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS API (private only unless public_endpoint is true)."
  value       = module.compute.cluster_endpoint
}

output "cluster_name" {
  description = "Name of the EKS cluster, used by scripts/eks-tunnel.sh."
  value       = module.compute.cluster_name
}

output "ecr_registry_host" {
  description = "ECR registry host for docker login and image names, without scheme or path."
  value       = "${var.aws_account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com"
}

output "ecr_repository_url" {
  description = "URL of the portfolio-web ECR repository."
  value       = aws_ecr_repository.web.repository_url
}

output "external_secrets_role_arn" {
  description = "ARN of the External Secrets Pod Identity role."
  value       = module.compute.external_secrets_role_arn
}

output "load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller Pod Identity role."
  value       = module.compute.load_balancer_controller_role_arn
}

output "node_group_name" {
  description = "Name of the managed node group."
  value       = module.compute.node_group_name
}

output "public_subnet_ids" {
  description = "IDs of the two public subnets."
  value       = module.network.public_subnet_ids
}

output "night_shutdown_flag_parameter" {
  description = "SSM parameter that switches the night shutdown on. null while night_shutdown_enabled is false. Not secret."
  value       = try(module.night_scheduler[0].flag_parameter_name, null)
}

output "night_shutdown_function_name" {
  description = "Name of the night shutdown reconcile Lambda, for a manual test run. null while night_shutdown_enabled is false."
  value       = try(module.night_scheduler[0].function_name, null)
}

output "tf_apply_role_arn" {
  description = "ARN of the apply role for portfolio-infra (GitHub secret AWS_TF_APPLY_ROLE_ARN, environment production)."
  value       = aws_iam_role.tf_apply.arn
}

output "tf_plan_role_arn" {
  description = "ARN of the plan role for portfolio-infra (GitHub secret AWS_TF_PLAN_ROLE_ARN)."
  value       = aws_iam_role.tf_plan.arn
}

output "vpc_id" {
  description = "ID of the VPC, used by the AWS Load Balancer Controller."
  value       = module.network.vpc_id
}

output "web_ci_role_arn" {
  description = "ARN of the role that portfolio-web CI assumes with OIDC (GitHub secret AWS_ROLE_ARN)."
  value       = aws_iam_role.web_ci.arn
}
