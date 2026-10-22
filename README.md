# portfolio-infra

Terraform for [portfolio-web](https://github.com/vudaian24/portfolio-web), a personal portfolio site. Region `ap-southeast-1`.

**Status:** `bootstrap/` and `envs/prod` (network, secrets, ECR, GitHub OIDC) are implemented. The EKS, DNS and Budgets parts are still planned.

The site is served by Vercel today. The move to AWS is planned for a run of about 44 days, paid by the account's credits. Its design records live in the private workspace repo, not in this repository.

## Target architecture (planned)

- **Cloudflare** keeps DNS and proxies the site: TLS for visitors, caching, WAF and one rate limiting rule. The Cloudflare provider manages the records, all proxied.
- **VPC** with two public subnets in two AZs and an internet gateway. No NAT gateway.
- **Amazon EKS** (Kubernetes 1.36) with one managed node, t4g.medium, Amazon Linux 2023 arm64, 20 GB gp3. The API endpoint accepts only the admin IP allow-list.
- **ALB**, created in the cluster by the AWS Load Balancer Controller, with an ACM certificate. Its security group admits TCP 443 from Cloudflare IP ranges only.
- In the cluster, deployed by **Argo CD** from [portfolio-gitops](https://github.com/vudaian24/portfolio-gitops): the Load Balancer Controller, External Secrets Operator, kube-prometheus-stack and the app. This repository holds no Kubernetes manifests.
- **SSM Parameter Store** (SecureString) holds the Telegram secrets. Terraform creates placeholder values; real values are set out of band with the AWS CLI.
- **ECR** stores the app image with immutable tags (git SHA).
- **GitHub OIDC** roles, the ECR repository, the ACM certificate and AWS Budgets live in `envs/prod`. CI assumes the roles. Humans use short-term `aws login` sessions.

Terraform uses only the AWS and Cloudflare providers. It never calls the Kubernetes API.

## Layout

Status of each directory today:

```text
bootstrap/            S3 bucket for Terraform state. Implemented. Its own state lives in that bucket.
envs/
  prod/               The only environment. Implemented: network, secrets, ECR, GitHub OIDC. Not yet: EKS, DNS.
modules/
  network/            Implemented: VPC, public subnets, internet gateway, ALB security group.
  secrets/            Implemented: SSM SecureString placeholders.
  compute/            Planned: EKS cluster, node group, EKS add-ons, Pod Identity. Stub.
  dns/                Planned: Cloudflare records and rate limiting rule. Stub.
.github/workflows/
  terraform-ci.yml    Format, validate, TFLint and trivy config on push to main and on pull requests.
```

Each environment directory calls the local modules and has its own backend, variables and state, following the [HashiCorp style guide](https://developer.hashicorp.com/terraform/language/style).

### Planned modules

| Module | Purpose | Status |
| --- | --- | --- |
| `network` | VPC, two public subnets with the ELB subnet tag, internet gateway, route table, ALB security group (443 from Cloudflare only) | Implemented |
| `compute` | EKS cluster, access entries, managed node group and launch template, EKS add-ons, node role, Pod Identity associations | Planned, stub |
| `dns` | Cloudflare records (proxied CNAMEs to the ALB, ACM validation) and the rate limiting rule | Planned, stub |
| `secrets` | SSM SecureString parameters with placeholder values (write-only) | Implemented |

The GitHub OIDC provider and role and the ECR repository are in `envs/prod/main.tf`. The ACM certificate and AWS Budgets are planned there too, not in a module.

## Requirements

- Terraform (version in `.terraform-version`, at least 1.11 for write-only SSM arguments)
- AWS CLI v2, authenticated with `aws login`. Do not create or use long-lived access keys.
- TFLint (optional, for local linting)
- The Argo CD bootstrap reads the outputs `ecr_registry_host` and `vpc_id` from `envs/prod`; its charts and manifests are in `portfolio-gitops`

## Usage

Account-specific values are kept out of the repository (`backend.hcl`, `account.auto.tfvars`). For `bootstrap/`, see [bootstrap/README.md](bootstrap/README.md). The steps below use `envs/prod`, the only environment. Before the first run, copy the example files and fill them in:

```sh
cd envs/prod
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
- `terraform init -backend=false` and `terraform validate` for `bootstrap` and `envs/prod`
- `tflint --recursive` with the `aws` ruleset, using TFLint v0.64.0
- `trivy config` (HIGH and CRITICAL fail the job)

CI has no plan or apply job yet.

Run the same checks locally:

```sh
terraform fmt -check -recursive
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"
```
