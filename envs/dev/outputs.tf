output "name_prefix" {
  description = "Resource name prefix of the environment."
  value       = local.name_prefix
}

output "region" {
  description = "AWS region of the environment."
  value       = var.region
}
