# secrets

SSM SecureString parameters under a path prefix (`/portfolio/prod/*`), each created with a placeholder value.

- `value_wo` (write-only) holds the placeholder. Write-only values are never stored in state, and the provider does not read them back.
- `value_wo_version` is bumped only to write a new placeholder. Real values are set with the AWS CLI, see [runbooks/secrets.md](../../../docs/runbooks/secrets.md). Changing `value_wo_version` would overwrite the real value with the placeholder, so do not bump it.
- Requires Terraform 1.11 or later.

| Parameter | Content |
| --- | --- |
| `/portfolio/prod/telegram-bot-token` | Telegram bot token |
| `/portfolio/prod/telegram-chat-id` | Telegram chat ID |
| `/portfolio/prod/grafana-admin-password` | Grafana admin password |

Not called yet. External Secrets Operator's IAM policy (`ssm:GetParameter*` on `/portfolio/prod/*`) belongs to the `compute` module and is not written yet.
