# network

The VPC for the EKS cluster and the ALB security group.

- VPC `portfolio-prod-vpc`, `10.0.0.0/16` (`vpc_cidr`), DNS support and hostnames on.
- Two public subnets `portfolio-prod-public-a` and `-b` in two AZs, `/24` each, tagged `kubernetes.io/role/elb = 1`, public IP on launch (the node needs one; there is no NAT gateway).
- Internet gateway and one public route table with `0.0.0.0/0` to the gateway.
- Default security group locked down: no rules.
- ALB security group `portfolio-prod-web` (Name tag, which the AWS Load Balancer Controller matches): inbound TCP 443 from Cloudflare's IPv4 ranges only (`cloudflare_ipv4_cidrs`, validated), outbound TCP `app_port` (3000) inside the VPC.
- No VPC flow logs: the design has no CloudWatch logs. The trivy ignores are on purpose; see the comments in `main.tf`.

Stub status: complete for this scope. The Cloudflare range list was fetched from https://www.cloudflare.com/ips-v4 on 2026-10-22.
