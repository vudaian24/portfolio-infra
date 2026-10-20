output "region" {
  description = "Region of the state bucket, used in each env's backend.tf."
  value       = var.region
}

output "state_bucket_name" {
  description = "Name of the state bucket, used in each env's backend.tf."
  value       = aws_s3_bucket.tfstate.bucket
}
