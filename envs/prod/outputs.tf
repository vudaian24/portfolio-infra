output "alb_security_group_id" {
  description = "ID of the ALB security group portfolio-prod-web (443 from Cloudflare only)."
  value       = module.network.alb_security_group_id
}

output "ecr_registry_host" {
  description = "ECR registry host for docker login and image names, without scheme or path."
  value       = "${var.aws_account_id}.dkr.ecr.${data.aws_region.current.region}.amazonaws.com"
}

output "ecr_repository_url" {
  description = "URL of the portfolio-web ECR repository."
  value       = aws_ecr_repository.web.repository_url
}

output "public_subnet_ids" {
  description = "IDs of the two public subnets."
  value       = module.network.public_subnet_ids
}

output "vpc_id" {
  description = "ID of the VPC, used by the AWS Load Balancer Controller."
  value       = module.network.vpc_id
}

output "web_ci_role_arn" {
  description = "ARN of the role that portfolio-web CI assumes with OIDC (GitHub secret AWS_ROLE_ARN)."
  value       = aws_iam_role.web_ci.arn
}
