# network

Planned: the VPC for the EKS cluster.

- VPC `10.0.0.0/16` with two public subnets in two AZs (EKS and the ALB need two), an internet gateway, and a route table with `0.0.0.0/0` to the gateway.
- Subnets tagged `kubernetes.io/role/elb = 1` so the AWS Load Balancer Controller can place the ALB.
- No NAT gateway. The node reaches the internet through its public IP.
- ALB security group `portfolio-prod-web`: inbound TCP 443 from Cloudflare's published IPv4 ranges only.

Stub today: only `terraform.tf` has content. The target design is in the parent workspace `docs/`.
