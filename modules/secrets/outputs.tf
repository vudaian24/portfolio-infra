output "parameter_arns" {
  description = "ARNs of the SecureString parameters, keyed by name. Used by IAM policies for External Secrets (later)."
  value       = { for name, parameter in aws_ssm_parameter.secret : name => parameter.arn }
}
