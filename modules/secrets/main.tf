locals {
  # Written once. Real values are set with `aws ssm put-parameter --overwrite`,
  # which Terraform does not track (write-only values are never stored in state).
  placeholder_value = "PLACEHOLDER-SET-WITH-AWS-CLI"
}

resource "aws_ssm_parameter" "secret" {
  for_each = var.parameter_names

  name             = "${var.path_prefix}/${each.key}"
  type             = "SecureString"
  value_wo         = local.placeholder_value
  value_wo_version = 1
}
