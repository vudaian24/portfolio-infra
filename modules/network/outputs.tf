output "alb_security_group_id" {
  description = "ID of the ALB security group (Name tag portfolio-prod-web)."
  value       = aws_security_group.alb.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, one per AZ."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.main.id
}
