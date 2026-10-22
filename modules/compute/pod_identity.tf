data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    sid     = "EksPodIdentityAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# AWS Load Balancer Controller. Policy file: AWS-published iam_policy.json of
# kubernetes-sigs/aws-load-balancer-controller tag v3.6.1, matching the chart in
# portfolio-gitops (chart version 3.6.1). Vendored, unmodified.
resource "aws_iam_role" "load_balancer_controller" {
  name               = "${var.name_prefix}-lb-controller"
  description        = "AWS Load Balancer Controller of ${var.name_prefix} (EKS Pod Identity)"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_policy" "load_balancer_controller" {
  name        = "${var.name_prefix}-aws-load-balancer-controller"
  description = "AWS Load Balancer Controller v3.6.1 policy (vendored from kubernetes-sigs/aws-load-balancer-controller)"
  policy      = file("${path.module}/policies/aws-load-balancer-controller-iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "load_balancer_controller" {
  role       = aws_iam_role.load_balancer_controller.name
  policy_arn = aws_iam_policy.load_balancer_controller.arn
}

resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = var.load_balancer_controller_service_account.namespace
  service_account = var.load_balancer_controller_service_account.name
  role_arn        = aws_iam_role.load_balancer_controller.arn

  depends_on = [aws_eks_addon.base]
}

# External Secrets Operator, Parameter Store provider. Read-only on the portfolio prefix.
data "aws_iam_policy_document" "external_secrets" {
  statement {
    sid    = "ReadPortfolioParameters"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = ["arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter${var.secrets_path_prefix}/*"]
  }

  # SecureString values use the AWS managed key aws/ssm. IAM still needs kms:Decrypt on it,
  # so the permission is limited to calls that come through SSM in this account.
  statement {
    sid       = "DecryptThroughSsm"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_policy" "external_secrets" {
  name        = "${var.name_prefix}-external-secrets"
  description = "External Secrets Operator: read ${var.secrets_path_prefix}/* from SSM Parameter Store"
  policy      = data.aws_iam_policy_document.external_secrets.json
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.name_prefix}-external-secrets"
  description        = "External Secrets Operator of ${var.name_prefix} (EKS Pod Identity)"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = var.external_secrets_service_account.namespace
  service_account = var.external_secrets_service_account.name
  role_arn        = aws_iam_role.external_secrets.arn

  depends_on = [aws_eks_addon.base]
}
