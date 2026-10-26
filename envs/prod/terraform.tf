terraform {
  # Write-only arguments (ssm value_wo) need >= 1.11; use_lockfile needs >= 1.10
  required_version = ">= 1.11"

  required_providers {
    # Zips the night_scheduler Lambda at plan time (modules/night_scheduler).
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}
