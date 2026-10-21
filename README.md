# portfolio-infra

Terraform for [portfolio-web](https://github.com/vudaian24/portfolio-web), a personal portfolio site. Region `ap-southeast-1`.

**Status:** `bootstrap/` is implemented. Environments and modules are scaffolding. The AWS target below is planned.

The site is served by Vercel today. The move to AWS is planned for a run of 2 to 3 months. Its design records live in the private workspace repo, not in this repository.

## Target architecture (planned)

- **Cloudflare** keeps DNS and proxies the site: TLS for visitors, caching, WAF and one rate limiting rule. The Cloudflare provider manages the records, all proxied.
- **VPC** with one public subnet in one AZ and an internet gateway. No NAT gateway and no load balancer.
- **EC2** (t4g.small, Amazon Linux 2023 arm64) with an Elastic IP runs Docker Compose: Caddy, with a Cloudflare Origin CA certificate, in front of the Next.js container. The security group admits TCP 443 from Cloudflare IP ranges only. SSH is closed; admin access uses SSM Session Manager.
- **SSM Parameter Store** (SecureString) holds the Telegram bot secrets and the Origin CA certificate and key. Terraform creates placeholder values; real values are set out of band with the AWS CLI.
- **ECR** stores the app image with immutable tags (git SHA). Deploys run the deploy script on the instance through SSM Run Command.
- **CloudWatch** keeps container logs and alarms on EC2 status checks, with an SNS email topic. **AWS Budgets** warns on spend.
- **GitHub OIDC** roles, the ECR repository and AWS Budgets live in `envs/prod`. CI assumes the roles. Humans use short-term `aws login` sessions.

No CloudFront, Lambda or S3 bucket for static assets.

## Layout

Status of each directory today:

```text
bootstrap/            S3 bucket for Terraform state. Implemented. Its own state lives in that bucket.
envs/
  dev/                Scaffolding. To be removed. Providers and backend are set; module calls are commented out.
  prod/               Target single environment. Stub: terraform.tf, backend.tf and the lock file today.
modules/
  network/            Planned: VPC, public subnet, internet gateway, security group. Stub.
  compute/            Planned: EC2 instance, Elastic IP, instance profile, user data. Stub.
  dns/                Planned: Cloudflare records and rate limiting rule. Stub.
  secrets/            Planned: SSM SecureString parameters. Stub.
.github/workflows/
  terraform-ci.yml    Format, validate and TFLint on push to main and on pull requests.
```

Each environment directory calls the local modules and has its own backend, variables and state, following the [HashiCorp style guide](https://developer.hashicorp.com/terraform/language/style).

### Planned modules

| Module | Purpose | Status |
| --- | --- | --- |
| `network` | VPC, one public subnet, internet gateway, route table, security group (443 from Cloudflare only) | Planned, stub |
| `compute` | EC2 instance, Elastic IP, instance profile, user data (Compose file, Caddyfile, deploy script) | Planned, stub |
| `dns` | Cloudflare records (proxied) and the rate limiting rule for the contact endpoint | Planned, stub |
| `secrets` | SSM SecureString parameters with placeholder values | Planned, stub |
| `monitoring` | CloudWatch log group, EC2 status alarms with recovery, SNS topic | Planned |

The GitHub OIDC roles, the ECR repository and AWS Budgets are planned directly in `envs/prod`, not in a module.

## Requirements

- Terraform (version in `.terraform-version`, at least 1.10 for S3 native state locking)
- AWS CLI v2, authenticated with `aws login`. Do not create or use long-lived access keys.
- TFLint (optional, for local linting)

## Usage

Account-specific values are kept out of the repository (`backend.hcl`, `account.auto.tfvars`). For `bootstrap/`, see [bootstrap/README.md](bootstrap/README.md). The steps below use `envs/dev`, the only environment with all example files today. Other environments follow the same pattern. Before the first run in an environment, copy the example files and fill them in:

```sh
cd envs/dev
cp backend.hcl.example backend.hcl                  # state bucket name from bootstrap/
cp account.auto.tfvars.example account.auto.tfvars  # AWS account ID (or set TF_VAR_aws_account_id)
```

Then:

```sh
aws login
terraform init -backend-config=backend.hcl
terraform plan
```

Apply is not run by hand in the target design. It runs in CI through the `production` GitHub environment, with manual approval.

## Checks

CI (`.github/workflows/terraform-ci.yml`) runs on every push to `main` and on pull requests. It uses no AWS credentials:

- `terraform fmt -check -recursive -diff`
- `terraform init -backend=false` and `terraform validate` for `bootstrap`, `envs/dev` and `envs/prod`
- `tflint --recursive` with the `aws` ruleset, using TFLint v0.64.0

CI has no plan or apply job yet.

Run the same checks locally:

```sh
terraform fmt -check -recursive
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"
```
