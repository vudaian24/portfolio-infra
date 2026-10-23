environment = "prod"
region      = "ap-southeast-1"

alb_ready = true
cutover   = true

# Break-glass only: true opens the public EKS endpoint to admin_cidrs (account.auto.tfvars and
# the TF_ADMIN_CIDRS secret, which must then hold the same list). Admins use scripts/eks-tunnel.sh.
public_endpoint = false

node_release_version = "1.36.5-20261019"
