environment = "prod"
region      = "ap-southeast-1"

# Phase 2: infrastructure. Phase 3: set alb_ready = true after Argo CD created the Ingress.
# Phase 4: set cutover = true (with the import in docs/runbooks/dns-cutover.md).
alb_ready = false
cutover   = false

# Pinned in Phase 2 after the first apply shows the recommended release (cluster-operations.md).
node_release_version = null
