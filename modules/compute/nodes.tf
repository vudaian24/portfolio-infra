data "aws_iam_policy_document" "node_trust" {
  statement {
    sid     = "Ec2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-eks-node"
  description        = "Worker node of ${var.name_prefix}: kubelet, ECR pull and VPC CNI (design: Identity layer)"
  assume_role_policy = data.aws_iam_policy_document.node_trust.json
}

# Worker, ECR pull and CNI policies as the design requires. AmazonEKS_CNI_Policy on the node
# role is broader than needed; a dedicated Pod Identity role for vpc-cni is the alternative.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryPullOnly",
    "AmazonEKS_CNI_Policy",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/${each.key}"
}

# Session Manager on the node: admins reach the private API endpoint through a port
# forwarding session (scripts/eks-tunnel.sh) instead of an IP allow-list. These are the five
# actions AWS lists for a custom Session Manager instance role. AmazonSSMManagedInstanceCore
# is not used: it also allows ssm:GetParameter and GetParameters on every parameter.
data "aws_iam_policy_document" "node_session_manager" {
  statement {
    sid    = "SessionManager"
    effect = "Allow"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "node_session_manager" {
  name        = "${var.name_prefix}-node-session-manager"
  description = "Session Manager on the ${var.name_prefix} node: port forwarding to the private EKS endpoint"
  policy      = data.aws_iam_policy_document.node_session_manager.json
}

resource "aws_iam_role_policy_attachment" "node_session_manager" {
  role       = aws_iam_role.node.name
  policy_arn = aws_iam_policy.node_session_manager.arn
}

# Launch template without an AMI: EKS keeps the AL2023 image and its bootstrap. The node
# subnet and instance type stay in the node group (prohibited in the template).
# IMDSv2 only with hop limit 1, so pods cannot reach the node role credentials.
# maxPods is not set here: a managed node group without a custom AMI caps it at 110 and
# ignores NodeConfig maxPods (docs/eks choosing-instance-type, "How maxPods is determined").
resource "aws_launch_template" "node" {
  name                   = "${var.name_prefix}-default"
  description            = "Managed node group ${var.name_prefix}-default: IMDSv2, hop limit 1, encrypted gp3 root"
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_root_volume_size
      volume_type           = "gp3"
      encrypted             = "true"
      delete_on_termination = "true"
    }
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name_prefix}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.public_subnet_ids

  # Public subnet: the node has a public IP (no NAT gateway in the design).
  ami_type        = "AL2023_ARM_64_STANDARD"
  instance_types  = [var.node_instance_type]
  capacity_type   = "ON_DEMAND"
  release_version = var.node_release_version

  # One node, one AZ. Desired = min = max, so the group never scales (ADR 0003).
  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  # The CNI and kube-proxy must exist before the node registers (bootstrap_self_managed_addons = false).
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.base,
  ]
}
