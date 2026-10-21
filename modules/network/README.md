# network

Planned: the VPC for the web instance.

- VPC `10.0.0.0/16` with one public subnet in one AZ, an internet gateway, and a route table with `0.0.0.0/0` to the gateway.
- No NAT gateway and no load balancer. The instance reaches the internet through its public IP.
- Security group for the instance: inbound TCP 443 from Cloudflare's published IPv4 ranges only, no SSH; outbound TCP 443.

Stub today: only `terraform.tf` has content. The target design is in the parent workspace `docs/`.
