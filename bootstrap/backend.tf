# Bootstrap state lives in the bucket this directory creates. The bucket name
# contains the AWS account ID, so it lives in backend.hcl (not committed).
# See backend.hcl.example, and README.md for the first run in a new account.
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
