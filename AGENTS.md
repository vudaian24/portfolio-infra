# AGENTS.md — portfolio-infra

Terraform for the portfolio on AWS, region `ap-southeast-1`. Public repo: github.com/vudaian24/portfolio-infra. Migration design and cross-repo rules live in the parent `../docs/`; this file covers this repo only.

## Versions (verified in files)

- Terraform 1.16.6 (`.terraform-version`). `required_version = ">= 1.10"` (needed for `use_lockfile` S3 locking).
- AWS provider `hashicorp/aws ~> 6.0`. Lock files `.terraform.lock.hcl` are committed; commit lock changes with provider changes.
- TFLint with `.tflint.hcl`: `terraform` plugin (recommended preset) and `aws` plugin 0.49.0. CI uses TFLint v0.64.0.

## Current state

- `bootstrap/`: implemented. Creates the state bucket `portfolio-tfstate-<account_id>` with versioning, SSE-S3, public access blocked, TLS-only policy and `prevent_destroy`. Its own state lives in that bucket (key `bootstrap/terraform.tfstate`, partial S3 backend; bucket name in the git-ignored `backend.hcl`). Run once per account; the first run in a new account is described in `bootstrap/README.md`.
- `envs/dev/`: providers, backend partial config, locals, variables and outputs are present. Module calls in `main.tf` are commented out. Scheduled for removal (single `prod` environment).
- `envs/prod/`: stub. `terraform.tf`, `backend.tf` (partial S3 backend, key `prod/terraform.tfstate`), `backend.hcl.example` and the lock file have content. `providers.tf`, `variables.tf`, `locals.tf`, `main.tf`, `outputs.tf` and `terraform.tfvars` are empty.
- `modules/network`, `compute`, `dns`, `secrets`: stubs. Only `terraform.tf` has content. All four are planned for the EKS target: `network` (VPC, two public subnets, internet gateway, ALB security group), `compute` (EKS cluster, access entries, node group, EKS add-ons, Pod Identity), `dns` (Cloudflare records and rate limiting rule), `secrets` (SSM parameters). Each module `README.md` states its scope.
- No Kubernetes manifests here. Argo CD config and the app chart live in the `portfolio-gitops` repository (parent `../docs/adr/0007-separate-gitops-repository.md`). Do not add a `k8s/` directory. Terraform uses only the AWS and Cloudflare providers and never manages in-cluster resources; `envs/prod` will expose the outputs `ecr_registry_host` and `vpc_id` for the Argo CD bootstrap (planned).
- The target design is in the parent `docs/`. Follow the parent docs when they conflict.

## Commands

Run from the repo root unless noted.

- Format check (CI uses `-diff`): `terraform fmt -check -recursive`. Fix with `terraform fmt -recursive` only when asked to change files.
- Validate, no AWS credentials needed. Per directory, for `bootstrap`, `envs/dev` and `envs/prod`:
  `cd <dir> && terraform init -backend=false -input=false && terraform validate`
  Note: `init` writes `.terraform/` (git-ignored).
- Lint: `tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"`
- Plan (needs AWS login; run only when the user asks):
  `cd envs/dev && cp backend.hcl.example backend.hcl` (fill in bucket from `terraform -chdir=../../bootstrap output -raw state_bucket_name`), then `aws login`, then `terraform init -backend-config=backend.hcl` and `terraform plan`.
- Apply: never run it. CI and a human do that.

## Conventions

- Project name `portfolio` (`var.project`). Resource names: `${project}-${environment}-<name>`. `envs/dev/locals.tf` builds `name_prefix = "${project}-${environment}"`.
- `default_tags` come from `local.common_tags`: `Project`, `Environment`, `ManagedBy = "terraform"`. Keep them.
- Every env provider sets `allowed_account_ids = [var.aws_account_id]`. Keep this guard in every new env.
- `aws_account_id` must be 12 digits (validated). It is supplied via `account.auto.tfvars` or `TF_VAR_aws_account_id`.
- State backend: S3 with `use_lockfile = true` and `encrypt = true`. Do not add DynamoDB locking.
- Env layout: each env has `terraform.tf`, `backend.tf`, `providers.tf`, `locals.tf`, `variables.tf`, `main.tf`, `outputs.tf`, plus `terraform.tfvars` (non-secret values only).
- Modules are local (`source = "../../modules/<name>"`). Each module has `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tf`, `README.md`.
- Follow the HashiCorp style guide for naming and layout.

## CI today (`.github/workflows/terraform-ci.yml`)

Runs on push to `main` and on every PR. Permissions: `contents: read`.

- `fmt`: `terraform fmt -check -recursive -diff`.
- `validate` (matrix: `bootstrap`, `envs/dev`, `envs/prod`): `terraform init -backend=false -input=false`, then `terraform validate`. No AWS credentials in CI.
- `tflint`: `tflint --init` then `tflint --recursive --config ... --format compact`.
- CI has no plan or apply job today. The target design (GitHub Actions with OIDC, human approval for apply) is described in the parent `docs/`.

## Never do

- Never run `terraform apply`, `terraform destroy`, `terraform import`, `terraform state rm` or `terraform state mv` without the user's explicit instruction in this session.
- Never commit `backend.hcl`, `account.auto.tfvars`, `*.tfstate*`, `*.tfplan`, `.terraform/`, or crash logs. `.gitignore` covers them; do not work around it.
- Never print or paste state contents, plan output containing secrets, or the account ID into commits, PRs or chat.
- Never open `~/.aws/*`. Use only short-term `aws login` credentials. Never create access keys.
- Do not remove `prevent_destroy` from the bootstrap state bucket, and do not turn off `allowed_account_ids`.
- Do not put secrets in `.tf` or `.tfvars` files. Store secret values in SSM Parameter Store (target design) and reference them by name.
- This repo is also checked out as a submodule of the `portfolio` workspace repo. Push changes here first; the workspace records the new commit afterwards.
- Commit on `main` and push it directly. Do not open pull requests.

## Parent docs

Target AWS architecture (Cloudflare proxy, ALB, one-node Amazon EKS cluster, Argo CD GitOps from `portfolio-gitops`, `envs/prod`, OIDC CI/CD) and runbooks are in `../docs/` (architecture, `adr/`, `runbooks/`). Read them before adding modules or changing envs.
