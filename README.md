# portfolio-infra

Terraform infrastructure for [portfolio-web](https://github.com/vudaian24/portfolio-web) on AWS (`ap-southeast-1`).

## Layout

```
bootstrap/        S3 bucket for Terraform remote state (run once, local state)
modules/
  network/        VPC, subnets, security groups
  compute/        EC2 instance running the Docker image
  dns/            Route 53 records
  secrets/        SSM Parameter Store values
envs/
  dev/            dev environment (state: s3://.../dev/terraform.tfstate)
  prod/           prod environment
```

Each environment directory calls the local modules and has its own backend, variables and state, following the [HashiCorp style guide](https://developer.hashicorp.com/terraform/language/style).

## Requirements

- Terraform (version in `.terraform-version`)
- AWS CLI v2, authenticated with `aws login`
- TFLint (optional, for local linting)

## Usage

Account-specific values are kept out of the repository. Before the first run in an environment, copy the example files and fill them in:

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

## Checks

CI (`.github/workflows/terraform-ci.yml`) runs on every push to `main` and on pull requests:

- `terraform fmt -check -recursive`
- `terraform init -backend=false` + `terraform validate` for `bootstrap`, `envs/dev`, `envs/prod`
- `tflint --recursive` with the `aws` ruleset

Run the same checks locally:

```sh
terraform fmt -check -recursive
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"
```
