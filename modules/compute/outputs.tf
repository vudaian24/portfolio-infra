output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.main.arn
}

output "cluster_endpoint" {
  description = "Endpoint of the EKS API. Private only unless public_endpoint is true; admins reach it through scripts/eks-tunnel.sh."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "external_secrets_role_arn" {
  description = "ARN of the External Secrets Pod Identity role."
  value       = aws_iam_role.external_secrets.arn
}

output "load_balancer_controller_role_arn" {
  description = "ARN of the AWS Load Balancer Controller Pod Identity role."
  value       = aws_iam_role.load_balancer_controller.arn
}

output "node_group_name" {
  description = "Name of the managed node group."
  value       = aws_eks_node_group.default.node_group_name
}

output "node_group_asg_name" {
  description = "Name of the Auto Scaling group EKS created for the managed node group. EKS publishes AWS/AutoScaling group metrics for it, which is how the night shutdown alarms on an empty node group."
  value       = one(aws_eks_node_group.default.resources[0].autoscaling_groups[*].name)
}
