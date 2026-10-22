provider "aws" {
  region = var.region

  # Prevent applying to the wrong account by mistake
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Component = "bootstrap"
    }
  }
}
