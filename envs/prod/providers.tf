provider "aws" {
  region = var.region

  # Prevent applying to the wrong account by mistake
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.common_tags
  }
}

# Reads CLOUDFLARE_API_TOKEN from the environment (zone-scoped token, see docs/runbooks/secrets.md).
provider "cloudflare" {}
