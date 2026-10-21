# portfolio-infra

Terraform for [portfolio-web](https://github.com/vudaian24/portfolio-web), a personal portfolio site. Region `ap-southeast-1`. The ACM certificate and WAF used by CloudFront are in `us-east-1`.

**Status:** `bootstrap/` is implemented. Environments and modules are scaffolding. The AWS target below is planned.

The site is served by Vercel today. The move to AWS is planned. Its design records live in the private workspace repo, not in this repository.

## Target architecture (planned)

- **CloudFront** terminates TLS and routes requests. It uses an ACM certificate and AWS WAF, both in `us-east-1`.
- **S3** (private bucket, Origin Access Control) serves `/_next/static/*`.
- **Lambda** runs the Next.js app as an arm64 container image through the Lambda Web Adapter. It runs outside a VPC, so there are no VPC, subnets or EC2 instances.
- **SSM Parameter Store** (SecureString) holds the Telegram bot secrets. Terraform creates placeholder values; real values are set out of band with the AWS CLI.
- **Cloudflare** keeps DNS. The Cloudflare provider manages the records, DNS only.
- **GitHub OIDC** roles, an ECR repository and AWS Budgets live in `envs/prod`. CI assumes the roles. Humans use short-term `aws login` sessions.

## Layout

Status of each directory today:

```text
bootstrap/            S3 bucket for Terraform state. Implemented. Run once per account, local state.
envs/
  dev/                Scaffolding. To be removed. Providers and backend are set; module calls are commented out.
  prod/               Target single environment. Stub: only terraform.tf and the lock file today.
modules/
  network/            To be removed. The target design has no VPC.
  compute/            To be removed. The target design has no EC2.
  dns/                Planned: Cloudflare DNS records. Stub.
  secrets/            Planned: SSM SecureString parameters. Stub.
.github/workflows/
  terraform-ci.yml    Format, validate and TFLint on push to main and on pull requests.
```

Each environment directory calls the local modules and has its own backend, variables and state, following the [HashiCorp style guide](https://developer.hashicorp.com/terraform/language/style).

### Planned modules

| Module | Purpose | Status |
| --- | --- | --- |
| `static-assets` | Private S3 bucket for `/_next/static/*`, with OAC | Planned |
| `app-function` | Lambda function, alias `live`, function URL | Planned |
| `cdn` | CloudFront distribution, ACM certificate, WAF | Planned |
| `secrets` | SSM SecureString parameters with placeholder values | Planned |
| `dns` | Cloudflare DNS records | Planned |
| `monitoring` | CloudWatch log groups and alarms, SNS topic | Planned |

The GitHub OIDC roles, the ECR repository and AWS Budgets are planned directly in `envs/prod`, not in a module.

## Requirements

- Terraform (version in `.terraform-version`, at least 1.10 for S3 native state locking)
- AWS CLI v2, authenticated with `aws login`. Do not create or use long-lived access keys.
- TFLint (optional, for local linting)

## Usage

Account-specific values are kept out of the repository. The steps below use `envs/dev`, the only environment with example files today. Other environments follow the same pattern. Before the first run in an environment, copy the example files and fill them in:

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
