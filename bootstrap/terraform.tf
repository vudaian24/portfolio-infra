terraform {
  # use_lockfile (S3 native locking) requires Terraform >= 1.10
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # No backend: bootstrap state stays local (terraform.tfstate),
  # because the state bucket does not exist yet on the first run.
}
