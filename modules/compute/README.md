# compute

Planned: the EC2 instance that runs the site.

- t4g.small, Amazon Linux 2023 arm64. The AMI ID is pinned by the caller; bumping it replaces the instance.
- 20 GB gp3 root volume, encrypted. IMDSv2 required with hop limit 1, so containers cannot reach instance credentials.
- Elastic IP, so the instance can be replaced without a DNS change.
- Instance profile: `AmazonSSMManagedInstanceCore`, ECR pull for the app repository, `ssm:GetParameter` on `/portfolio/prod/*`, CloudWatch Logs write.
- User data installs Docker and the Compose plugin and writes `/opt/portfolio/compose.yaml`, `Caddyfile` and `deploy.sh`. `user_data_replace_on_change = true`.

Stub today: only `terraform.tf` has content. The target design is in the parent workspace `docs/`.
