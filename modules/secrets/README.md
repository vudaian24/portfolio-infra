# secrets

Planned: SSM SecureString parameters with placeholder values; real values set with the AWS CLI so they never enter state.

The parameters hold the Telegram bot token and chat ID. Terraform manages the parameter with `ignore_changes` on its value.
