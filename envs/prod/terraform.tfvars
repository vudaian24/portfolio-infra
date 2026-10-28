environment = "prod"
region      = "ap-southeast-1"

alb_ready = true
cutover   = true

# Break-glass only: true opens the public EKS endpoint to admin_cidrs (account.auto.tfvars).
# Admins use scripts/eks-tunnel.sh.
public_endpoint = false

node_release_version = "1.36.5-20261019"

# Argo CD through Cloudflare Access and a Tunnel (ADR 0009). Turn on only after the
# Zero Trust organization exists and both Cloudflare tokens have the account permissions
# (modules/admin_access/README.md). The email list is in account.auto.tfvars and a secret.
admin_access_enabled = false
# access_team_name   = "<team>"

# Scheduled night shutdown of the node group (ADR 0011). Creating it does not start it: the
# SSM parameter /portfolio/prod/night-shutdown-enabled holds "false" until it is set by hand
# (modules/night_scheduler/README.md). The site returns 503 for the whole window, which runs
# from Saturday 22:00 to Monday 08:00 because of the off day.
night_shutdown_enabled  = true
night_shutdown_start    = "22:00"
night_shutdown_end      = "08:00"
night_shutdown_off_days = ["Sun"]
