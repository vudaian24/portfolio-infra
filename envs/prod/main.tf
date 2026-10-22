data "aws_region" "current" {}

module "network" {
  source = "../../modules/network"

  name_prefix = local.name_prefix
}

module "secrets" {
  source = "../../modules/secrets"

  path_prefix = "/${var.project}/${var.environment}"
  parameter_names = toset([
    "telegram-bot-token",
    "telegram-chat-id",
    "grafana-admin-password",
  ])
}

# ECR repository for the app image. Tags are full git SHAs, so they never change.
resource "aws_ecr_repository" "web" {
  name                 = local.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  # Images are rebuilt from git, so the decommission run can delete the repository
  # even when it still holds images (docs/runbooks/decommission.md).
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "web" {
  repository = aws_ecr_repository.web.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after one day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}

# GitHub Actions OIDC. thumbprint_list is optional: AWS trusts GitHub's root CA itself.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "web_ci_trust" {
  statement {
    sid     = "GitHubActionsWebProduction"
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
      values   = ["${var.github_oidc_subject_prefix}:environment:${var.github_environment}"]
    }
  }
}

resource "aws_iam_role" "web_ci" {
  name               = local.web_ci_role_name
  assume_role_policy = data.aws_iam_policy_document.web_ci_trust.json
}

data "aws_iam_policy_document" "web_ci_ecr" {
  statement {
    sid       = "GetAuthorizationToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "PushPullWebRepository"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.web.arn]
  }
}

resource "aws_iam_role_policy" "web_ci_ecr" {
  name   = "ecr-push"
  role   = aws_iam_role.web_ci.id
  policy = data.aws_iam_policy_document.web_ci_ecr.json
}

module "compute" {
  source = "../../modules/compute"

  name_prefix         = local.name_prefix
  admin_cidrs         = var.admin_cidrs
  admin_principal_arn = var.admin_principal_arn
  cluster_version     = var.cluster_version
  deletion_protection = var.cluster_deletion_protection
  public_subnet_ids   = module.network.public_subnet_ids

  node_release_version = var.node_release_version
  secrets_path_prefix  = local.secrets_path_prefix
}

# The ALB is created by the AWS Load Balancer Controller from the Ingress, so it is looked up,
# not managed here. Read only when alb_ready is true (the ALB must exist first).
data "aws_lb" "web" {
  count = var.alb_ready ? 1 : 0

  name = local.alb_name
}

module "dns" {
  source = "../../modules/dns"

  acm_validation_records = {
    for domain in [var.production_hostname, var.test_hostname] : domain => {
      name  = trimsuffix(one([for dvo in aws_acm_certificate.web.domain_validation_options : dvo.resource_record_name if dvo.domain_name == domain]), ".")
      type  = one([for dvo in aws_acm_certificate.web.domain_validation_options : dvo.resource_record_type if dvo.domain_name == domain])
      value = trimsuffix(one([for dvo in aws_acm_certificate.web.domain_validation_options : dvo.resource_record_value if dvo.domain_name == domain]), ".")
    }
  }

  alb_ready    = var.alb_ready
  alb_dns_name = var.alb_ready ? data.aws_lb.web[0].dns_name : null
  cutover      = var.cutover

  production_hostname = var.production_hostname
  test_hostname       = var.test_hostname
}
