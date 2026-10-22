locals {
  # vpc-cni, kube-proxy and the Pod Identity agent must exist before the node registers.
  # coredns and metrics-server need a Ready node, so they wait for the node group.
  # Prefix delegation: t4g.medium allows 17 pods without it, and the design needs 21 to 23.
  addon_config = {
    "vpc-cni" = jsonencode({
      env = {
        ENABLE_PREFIX_DELEGATION = "true"
        WARM_PREFIX_TARGET       = "1"
      }
    })
  }

  base_addons     = toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])
  workload_addons = toset(["coredns", "metrics-server"])
}

# Versions: the EKS default version for the cluster Kubernetes version (most_recent = false).
# Terraform plans show a version change when AWS changes the default. Pin an explicit
# addon_version here if a change must be reviewed first.
data "aws_eks_addon_version" "this" {
  for_each = setunion(local.base_addons, local.workload_addons)

  addon_name         = each.key
  kubernetes_version = var.cluster_version
}

resource "aws_eks_addon" "base" {
  for_each = local.base_addons

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  configuration_values        = lookup(local.addon_config, each.key, null)
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "workload" {
  for_each = local.workload_addons

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.default]
}
