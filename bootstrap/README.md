# bootstrap

Creates the S3 bucket that stores Terraform state for the environments in `envs/`. Run it **once** per AWS account.

The bucket is configured with:

- Versioning: old state can be restored; noncurrent versions expire after `noncurrent_version_retention_days` days.
- SSE-S3 encryption, public access blocked, TLS-only access.
- `prevent_destroy` to guard against an accidental `terraform destroy`.

No DynamoDB table is needed: environments lock state with `use_lockfile = true` (S3 native locking, Terraform >= 1.10).

## Usage

```sh
cd bootstrap
terraform init
terraform apply
terraform output state_bucket_name
```

State for this directory is kept **local** (`terraform.tfstate`) because the bucket does not exist on the first run. If this file is lost, `terraform import` the bucket again.

## Using it in an environment

```hcl
# envs/<env>/backend.tf
terraform {
  backend "s3" {
    bucket       = "<state_bucket_name>"
    key          = "<env>/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
```
