# AGENTS.md — portfolio-infra

Terraform for the portfolio on AWS, region `ap-southeast-1`. Public repo: github.com/vudaian24/portfolio-infra. Migration design and cross-repo rules live in the parent `../docs/`; this file covers this repo only.

## Versions (verified in files)

- Terraform 1.16.6 (`.terraform-version`). `required_version = ">= 1.11"` (write-only arguments on `aws_ssm_parameter` need 1.11; `use_lockfile` needs 1.10).
- AWS provider `hashicorp/aws ~> 6.0`. Lock files `.terraform.lock.hcl` are committed; commit lock changes with provider changes.
- Cloudflare provider `cloudflare/cloudflare ~> 5.0` (only `envs/prod`, v5 names: `cloudflare_dns_record`, `cloudflare_ruleset`, `data "cloudflare_zone"` with `filter`). Token from `CLOUDFLARE_API_TOKEN`, never in a file.
- TFLint with `.tflint.hcl`: `terraform` plugin (recommended preset) and `aws` plugin 0.49.0. CI uses TFLint v0.64.0.

## Current state

- `bootstrap/`: implemented. State bucket `portfolio-tfstate-<account_id>` (versioning, SSE-S3, `prevent_destroy`). Run once per account.
- `envs/prod/`: the only environment, applied; the stack must be destroyed by 2026-12-01. It holds `network`, `secrets`, `compute` (EKS 1.36, one managed node, add-ons, Pod Identity), `dns` (Cloudflare v5), ACM, Budgets, ECR, the GitHub OIDC roles for portfolio-web and the Terraform plan and apply roles (`ci.tf`). Switches in `terraform.tfvars`: `alb_ready` and `cutover` (both `true`). `public_endpoint = false`: the EKS API is private, and admins reach it with `scripts/eks-tunnel.sh` (Session Manager); `true` is break-glass only.
- Terraform uses only the AWS and Cloudflare providers and never manages in-cluster resources (Argo CD, from `portfolio-gitops`).
- Design decisions and deviations are in `README.md` and each module README. The first apply runs from a laptop (`README.md`, First apply).

## Commands

Run from the repo root unless noted.

- Format check (CI uses `-diff`): `terraform fmt -check -recursive`. Fix with `terraform fmt -recursive` only when asked to change files.
- Validate, no AWS credentials needed. Per directory, for `bootstrap` and `envs/prod`:
  `cd <dir> && terraform init -backend=false -input=false && terraform validate`
  Note: `init` writes `.terraform/` (git-ignored).
- Lint: `tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"`
- Plan (needs AWS login; run only when the user asks):
  `cd envs/prod && cp backend.hcl.example backend.hcl` (fill in bucket from `terraform -chdir=../../bootstrap output -raw state_bucket_name`) and `cp account.auto.tfvars.example account.auto.tfvars` (fill in the account ID); then `aws login`, then `terraform init -backend-config=backend.hcl` and `terraform plan`.
- Lock files: `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` after `init -backend=false`, in each root that changes providers.
- Security scan: `trivy config --severity HIGH,CRITICAL .`
- Apply: never run it. CI and a human do that.

## Conventions

- Project name `portfolio` (`var.project`). Resource names: `${project}-${environment}-<name>`. `envs/prod/locals.tf` builds `name_prefix = "${project}-${environment}"`.
- `default_tags` come from `local.common_tags`: `Project`, `Environment`, `ManagedBy = "terraform"`. Keep them.
- Every env provider sets `allowed_account_ids = [var.aws_account_id]`. Keep this guard in every new env.
- `aws_account_id` must be 12 digits (validated). It is supplied via `account.auto.tfvars` or `TF_VAR_aws_account_id`.
- State backend: S3 with `use_lockfile = true` and `encrypt = true`. Do not add DynamoDB locking.
- Env layout: each env has `terraform.tf`, `backend.tf`, `providers.tf`, `locals.tf`, `variables.tf`, `main.tf`, `outputs.tf`, plus `terraform.tfvars` (non-secret values only). ECR and the OIDC role stay in `envs/prod/main.tf` (ADR 0004).
- Modules are local (`source = "../../modules/<name>"`). Each module has `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tf`, `README.md`.
- Follow the HashiCorp style guide for naming and layout.

## CI today (`.github/workflows/terraform-ci.yml`)

Permissions `contents: read`; OIDC `id-token: write` only in the plan and apply jobs. Every action is pinned to a commit SHA; checkout does not persist credentials.

- `fmt`, `validate` (matrix `bootstrap`, `envs/prod`, no credentials), `tflint`, `trivy`.
- `plan` (push to main and weekly schedule, only when the repository variable `TF_CI_ENABLED` is `true`): assumes the plan role (trusts `ref:refs/heads/main` only), stops if the plan changes IAM or EKS access entries (those are applied from a laptop), and saves the plan encrypted with `TF_PLAN_PASSPHRASE` as a one-day artifact. No environment.
- `apply` (push to main): environment `production` (reviewer approval), applies the saved plan only. Concurrency group never cancels.
- Secrets and variable names: see `README.md`.

`.github/workflows/notify-workspace.yml`: on push to `main`, sends `repository_dispatch` (`submodule-updated`) to the private workspace repo `portfolio`, which then bumps its submodule pointer. Uses a GitHub App token (repository variable `WORKSPACE_SYNC_APP_CLIENT_ID`, repository secret `WORKSPACE_SYNC_APP_PRIVATE_KEY`); skipped while the variable is unset.

## Never do

- Never run `terraform apply`, `terraform destroy`, `terraform import`, `terraform state rm` or `terraform state mv` without the user's explicit instruction in this session.
- Never commit `backend.hcl`, `account.auto.tfvars`, `*.tfstate*`, `*.tfplan`, `.terraform/`, or crash logs. `.gitignore` covers them; do not work around it.
- Never print or paste state contents, plan output containing secrets, or the account ID into commits, PRs or chat.
- Never open `~/.aws/*`. Use only short-term `aws login` credentials. Never create access keys.
- Do not remove `prevent_destroy` from the bootstrap state bucket, and do not turn off `allowed_account_ids`.
- Do not put secrets in `.tf` or `.tfvars` files. Store secret values in SSM Parameter Store and reference them by name.
- This repo is also checked out as a submodule of the `portfolio` workspace repo. Push changes here first; the workspace records the new commit afterwards.
- Commit on `main` and push it directly. Do not open pull requests.

## Parent docs

AWS architecture (Cloudflare proxy, ALB, one-node Amazon EKS cluster, Argo CD GitOps from `portfolio-gitops`, `envs/prod`, OIDC CI/CD) and runbooks are in `../docs/` (architecture, `adr/`, `runbooks/`). Read them before adding modules or changing envs.
