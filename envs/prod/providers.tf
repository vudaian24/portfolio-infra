provider "aws" {
  region = var.region

  # Prevent applying to the wrong account by mistake
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = local.common_tags
  }
}

# Token from the git-ignored secrets.auto.tfvars (template: secrets.auto.tfvars.example). The variable is
# ephemeral: the token stays out of the saved plan and the state, and apply <planfile> reads the file again.
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
