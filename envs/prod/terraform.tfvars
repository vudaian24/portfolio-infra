environment = "prod"
region      = "ap-southeast-1"

alb_ready = true
cutover   = true

# Break-glass only: true opens the public EKS endpoint to admin_cidrs (account.auto.tfvars and
# the TF_ADMIN_CIDRS secret, which must then hold the same list). Admins use scripts/eks-tunnel.sh.
public_endpoint = false

node_release_version = "1.36.5-20261019"

# Argo CD and Grafana through Cloudflare Access and a Tunnel (ADR 0009). Turn on only after the
# Zero Trust organization exists and both Cloudflare tokens have the account permissions
# (modules/admin_access/README.md). The email list is in account.auto.tfvars and a secret.
admin_access_enabled = false
# access_team_name   = "<team>"
