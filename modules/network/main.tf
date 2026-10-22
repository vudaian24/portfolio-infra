data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Two public subnets in two AZs: EKS and the ALB both need two
  public_subnets = {
    a = {
      availability_zone = data.aws_availability_zones.available.names[0]
      cidr_block        = cidrsubnet(var.vpc_cidr, 8, 0)
    }
    b = {
      availability_zone = data.aws_availability_zones.available.names[1]
      cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
    }
  }
}

# No VPC flow logs: the design has no CloudWatch logs (cost), and the VPC
# carries only the single public-facing app.
#trivy:ignore:AVD-AWS-0178
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

# Nothing uses the default security group, so it has no rules.
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

# Nodes need a public IP (no NAT gateway in the design), so auto-assign is intentional.
#trivy:ignore:AVD-AWS-0164
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.name_prefix}-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name_prefix}-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Security group of the ALB created by the AWS Load Balancer Controller.
# The controller matches it by the Name tag, so the tag must stay exact.
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-web"
  description = "ALB for portfolio-web: HTTPS from Cloudflare only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.name_prefix}-web"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_cloudflare" {
  for_each = toset(var.cloudflare_ipv4_cidrs)

  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS from Cloudflare"
}

# The ALB reaches pod IPs (target type ip) inside the VPC on the app port only.
resource "aws_vpc_security_group_egress_rule" "alb_app" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = aws_vpc.main.cidr_block
  from_port         = var.app_port
  to_port           = var.app_port
  ip_protocol       = "tcp"
  description       = "App port inside the VPC"
}
