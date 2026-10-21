# Partial backend configuration: the bucket name contains the AWS account ID,
# so it lives in backend.hcl (not committed). See backend.hcl.example.
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "prod/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
