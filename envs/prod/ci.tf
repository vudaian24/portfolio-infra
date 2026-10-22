# Roles for the portfolio-infra Terraform jobs (ADR 0002, ADR 0008). Created by the first apply
# from a laptop: the workflow cannot assume a role that does not exist yet. Later changes to
# this file are applied by the owner from a laptop too, because the apply role cannot change
# its own role (the Deny below).

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition

  # GitHub OIDC subjects (immutable format). The plan job runs on push to main and on the
  # weekly schedule (both on refs/heads/main). The apply job runs in the production environment.
  tf_plan_subject  = "${var.github_terraform_subject_prefix}:ref:refs/heads/main"
  tf_apply_subject = "${var.github_terraform_subject_prefix}:environment:${var.github_terraform_environment}"

  tfstate_bucket_arn = "arn:${local.partition}:s3:::${var.tfstate_bucket_name}"
  tfstate_key_prefix = "${var.environment}/"
}

data "aws_iam_policy_document" "tf_trust_plan" {
  statement {
    sid     = "GitHubPortfolioInfraMain"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.tf_plan_subject]
    }
  }
}

data "aws_iam_policy_document" "tf_trust_apply" {
  statement {
    sid     = "GitHubPortfolioInfraProduction"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.tf_apply_subject]
    }
  }
}

# Plan: read-only account access plus the state bucket. The lock file (use_lockfile) is the only
# write. ReadOnlyAccess may let the role read SSM parameter values (not verified; the plan refreshes
# aws_ssm_parameter). The trust is limited to main of portfolio-infra, so only merged code can run it.
resource "aws_iam_role" "tf_plan" {
  name               = local.tf_plan_role_name
  description        = "portfolio-infra plan job (main branch, OIDC)"
  assume_role_policy = data.aws_iam_policy_document.tf_trust_plan.json
}

resource "aws_iam_role_policy_attachment" "tf_plan_readonly" {
  role       = aws_iam_role.tf_plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "tf_plan_state" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.tfstate_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [local.tfstate_key_prefix, "${local.tfstate_key_prefix}*"]
    }
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${local.tfstate_bucket_arn}/${local.tfstate_key_prefix}*"]
  }

  statement {
    sid       = "StateLockFile"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.tfstate_bucket_arn}/${local.tfstate_key_prefix}terraform.tfstate.tflock"]
  }
}

resource "aws_iam_role_policy" "tf_plan_state" {
  name   = "state"
  role   = aws_iam_role.tf_plan.id
  policy = data.aws_iam_policy_document.tf_plan_state.json
}

# Apply: runs only in the production environment, which requires a reviewer, and applies the
# plan saved by the plan job. Allow-list below; no * resources except where AWS does not support
# resource ARNs (ec2 network, ACM request, Describe calls).
# It cannot write IAM (roles, policies, OIDC provider) or EKS access entries: a role that can
# write policies for roles it may pass is admin-equivalent. Those changes are applied from a
# laptop by the admin, and the plan job stops when a plan contains them.
resource "aws_iam_role" "tf_apply" {
  name               = local.tf_apply_role_name
  description        = "portfolio-infra apply job (production environment, OIDC)"
  assume_role_policy = data.aws_iam_policy_document.tf_trust_apply.json
}

data "aws_iam_policy_document" "tf_apply" {
  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.tfstate_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [local.tfstate_key_prefix, "${local.tfstate_key_prefix}*"]
    }
  }

  statement {
    sid       = "ReadWriteState"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.tfstate_bucket_arn}/${local.tfstate_key_prefix}*"]
  }

  statement {
    sid    = "EksClusterAndNodes"
    effect = "Allow"
    actions = [
      "eks:CreateCluster",
      "eks:DescribeCluster",
      "eks:UpdateClusterConfig",
      "eks:UpdateClusterVersion",
      "eks:DeleteCluster",
      "eks:TagResource",
      "eks:UntagResource",
      "eks:ListTagsForResource",
      "eks:DescribeAccessEntry",
      "eks:ListAccessEntries",
      "eks:ListAssociatedAccessPolicies",
      "eks:CreateNodegroup",
      "eks:DescribeNodegroup",
      "eks:UpdateNodegroupConfig",
      "eks:UpdateNodegroupVersion",
      "eks:DeleteNodegroup",
      "eks:CreateAddon",
      "eks:DescribeAddon",
      "eks:UpdateAddon",
      "eks:DeleteAddon",
      "eks:DescribeAddonConfiguration",
      "eks:CreatePodIdentityAssociation",
      "eks:DescribePodIdentityAssociation",
      "eks:UpdatePodIdentityAssociation",
      "eks:DeletePodIdentityAssociation",
      "eks:ListPodIdentityAssociations",
    ]
    resources = [
      "arn:${local.partition}:eks:${var.region}:${var.aws_account_id}:cluster/${local.name_prefix}",
      "arn:${local.partition}:eks:${var.region}:${var.aws_account_id}:nodegroup/${local.name_prefix}/*/*",
      "arn:${local.partition}:eks:${var.region}:${var.aws_account_id}:addon/${local.name_prefix}/*/*",
      "arn:${local.partition}:eks:${var.region}:${var.aws_account_id}:access-entry/${local.name_prefix}/*",
      "arn:${local.partition}:eks:${var.region}:${var.aws_account_id}:podidentityassociation/${local.name_prefix}/*",
    ]
  }

  statement {
    sid       = "EksReadOnlyCatalog"
    effect    = "Allow"
    actions   = ["eks:DescribeAddonVersions"]
    resources = ["*"]
  }

  # VPC, subnets, route tables, security groups and launch templates. AWS does not allow
  # resource ARNs for most create calls here, so the statement is limited to the region.
  statement {
    sid    = "NetworkAndLaunchTemplates"
    effect = "Allow"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcAttribute",
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:DescribeSubnets",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",
      "ec2:DescribeInternetGateways",
      "ec2:CreateInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:DescribeRouteTables",
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:ModifySecurityGroupRules",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid    = "EcrRepository"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:DeleteRepository",
      "ecr:PutLifecyclePolicy",
      "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:ListTagsForResource",
      "ecr:TagResource",
      "ecr:UntagResource",
      "ecr:ListImages",
      "ecr:DescribeImages",
      "ecr:BatchDeleteImage",
    ]
    resources = [
      "arn:${local.partition}:ecr:${var.region}:${var.aws_account_id}:repository/${local.ecr_repository_name}",
    ]
  }

  statement {
    sid    = "SecretParameters"
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:DeleteParameter",
      "ssm:AddTagsToResource",
      "ssm:RemoveTagsFromResource",
      "ssm:ListTagsForResource",
    ]
    resources = [
      "arn:${local.partition}:ssm:${var.region}:${var.aws_account_id}:parameter${local.secrets_path_prefix}/*",
    ]
  }

  statement {
    sid       = "SsmDescribe"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  # ACM certificates have no ARN before the request, so the statement is limited to the region.
  statement {
    sid    = "AcmCertificate"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:DescribeCertificate",
      "acm:GetCertificate",
      "acm:DeleteCertificate",
      "acm:ListCertificates",
      "acm:ListTagsForCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "acm:UpdateCertificateOptions",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid    = "BudgetsAndLoadBalancerRead"
    effect = "Allow"
    actions = [
      "budgets:ViewBudget",
      "budgets:ModifyBudget",
      "budgets:CreateBudget",
      "budgets:DeleteBudget",
      "budgets:CreateNotification",
      "budgets:UpdateNotification",
      "budgets:DeleteNotification",
      "budgets:CreateSubscriber",
      "budgets:UpdateSubscriber",
      "budgets:DeleteSubscriber",
      "budgets:DescribeSubscribersForNotification",
      "budgets:DescribeNotificationsForBudget",
      "budgets:TagResource",
      "budgets:UntagResource",
      "budgets:ListTagsForResource",
    ]
    resources = ["arn:${local.partition}:budgets::${var.aws_account_id}:budget/${local.name_prefix}-*"]
  }

  statement {
    sid       = "ReadOnlyDescribe"
    effect    = "Allow"
    actions   = ["budgets:DescribeBudget", "budgets:DescribeBudgets", "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeTags", "elasticloadbalancing:DescribeLoadBalancerAttributes"]
    resources = ["*"]
  }

  # IAM: read only. Writes are applied from a laptop (see the comment on aws_iam_role.tf_apply).
  statement {
    sid    = "IamRead"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:ListRoleTags",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:ListPolicyTags",
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviderTags",
    ]
    resources = [
      "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.name_prefix}-*",
      "arn:${local.partition}:iam::${var.aws_account_id}:policy/${local.name_prefix}-*",
      "arn:${local.partition}:iam::${var.aws_account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }

  # PassRole only for the four roles the cluster, the node group and the Pod Identity
  # associations use, so no other role can be handed to EKS or to a pod.
  statement {
    sid     = "PassKnownRolesToEks"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      for name in ["eks-cluster", "eks-node", "lb-controller", "external-secrets"] :
      "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.name_prefix}-${name}"
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["eks.amazonaws.com", "ec2.amazonaws.com", "pods.eks.amazonaws.com"]
    }
  }

  statement {
    sid       = "EksServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com"]
    }
  }

  # Explicit deny: the apply role cannot change its own role, the plan role or their policies.
  statement {
    sid    = "DenySelfModification"
    effect = "Deny"
    actions = [
      "iam:Create*",
      "iam:Delete*",
      "iam:Put*",
      "iam:Attach*",
      "iam:Detach*",
      "iam:Update*",
      "iam:Tag*",
      "iam:Untag*",
    ]
    resources = [
      "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.tf_plan_role_name}",
      "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.tf_apply_role_name}",
    ]
  }
}

resource "aws_iam_role_policy" "tf_apply" {
  name   = "portfolio-infra-apply"
  role   = aws_iam_role.tf_apply.id
  policy = data.aws_iam_policy_document.tf_apply.json
}
