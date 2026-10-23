environment = "prod"
region      = "ap-southeast-1"

# Phase 2: infrastructure. Phase 3: set alb_ready = true after Argo CD created the Ingress.
# Phase 4: set cutover = true; it creates the portfolio record (docs/runbooks/dns-cutover.md).
alb_ready = true
cutover   = true

# Admins reach the private EKS endpoint through Session Manager (scripts/eks-tunnel.sh).
# Break-glass only: true turns on the public endpoint for admin_cidrs (account.auto.tfvars and
# the TF_ADMIN_CIDRS secret, which must then hold the same list).
public_endpoint = false

# Pinned in Phase 2 after the first apply shows the recommended release (cluster-operations.md).
# 1.36.5-20261019 is the release EKS chose at creation on 2026-10-22, so pinning it changes nothing.
node_release_version = "1.36.5-20261019"
