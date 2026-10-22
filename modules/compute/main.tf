data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
}

data "aws_iam_policy_document" "eks_cluster_trust" {
  statement {
    sid     = "EksServiceAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.name_prefix}-eks-cluster"
  description        = "EKS control plane of ${var.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_trust.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

# Trivy ignores (each one justified):
# - AVD-AWS-0040: the public endpoint is on, on purpose. public_access_cidrs = admin_cidrs
#   limits it to the admin allow-list (aws-eks.md, Layers, Cluster); Trivy cannot see the CIDRs.
# - AVD-AWS-0038: no control plane logs. The design has no CloudWatch logs (aws-eks.md, Cost).
# - AVD-AWS-0039: no envelope encryption. A customer managed KMS key costs about 1 USD per month
#   and the design has none. Kubernetes Secrets copy SSM values that already sit in this account.
#trivy:ignore:AVD-AWS-0038
#trivy:ignore:AVD-AWS-0039
#trivy:ignore:AVD-AWS-0040
resource "aws_eks_cluster" "main" {
  name                          = var.name_prefix
  role_arn                      = aws_iam_role.eks_cluster.arn
  version                       = var.cluster_version
  bootstrap_self_managed_addons = false
  deletion_protection           = var.deletion_protection

  # API only: no aws-auth ConfigMap. No implicit cluster-creator admin, so the admin
  # principal below is the only human entry.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  # Standard support: extended support costs 0.50 USD per hour more.
  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids              = var.public_subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
    public_access_cidrs     = var.admin_cidrs
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:${local.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
