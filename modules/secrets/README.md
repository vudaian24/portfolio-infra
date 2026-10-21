# secrets

Planned: SSM SecureString parameters with placeholder values. Real values are set with the AWS CLI, so they never enter state. Terraform manages each parameter with `ignore_changes` on its value.

| Parameter | Content |
| --- | --- |
| `/portfolio/prod/telegram-bot-token` | Telegram bot token |
| `/portfolio/prod/telegram-chat-id` | Telegram chat ID |
| `/portfolio/prod/origin-cert` | Cloudflare Origin CA certificate |
| `/portfolio/prod/origin-key` | Private key of the Origin CA certificate |

Stub today: only `terraform.tf` has content. The target design is in the parent workspace `docs/`.
