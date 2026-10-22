# bootstrap

Creates the S3 bucket that stores Terraform state for the environments in `envs/`, and for this directory itself. Run it **once** per AWS account.

The bucket is configured with:

- Versioning: old state can be restored; noncurrent versions expire after `noncurrent_version_retention_days` days.
- SSE-S3 encryption, public access blocked, TLS-only access.
- `prevent_destroy` to guard against an accidental `terraform destroy`.

No DynamoDB table is needed: state is locked with `use_lockfile = true` (S3 native locking, Terraform >= 1.11).

## State

The state of this directory lives in the bucket it creates, under the key `bootstrap/terraform.tfstate`. `backend.tf` holds a partial S3 backend configuration. The bucket name contains the AWS account ID, so it goes in `backend.hcl`, which is git-ignored. Copy it from `backend.hcl.example`.

## First run in a new account

The bucket does not exist yet, so the first apply uses local state and then moves it into the bucket.

```sh
cd bootstrap
cp account.auto.tfvars.example account.auto.tfvars   # AWS account ID, git-ignored
mv backend.tf backend.tf.off          # first run only: local state
terraform init
terraform apply
terraform output -raw state_bucket_name
cp backend.hcl.example backend.hcl    # set bucket to the name above
mv backend.tf.off backend.tf
terraform init -backend-config=backend.hcl -migrate-state
terraform state list                  # check that state is read from S3
rm terraform.tfstate terraform.tfstate.backup
```

## Later runs

The directory checks `allowed_account_ids` against `aws_account_id`, so a wrong account fails before any change.

```sh
cd bootstrap
cp backend.hcl.example backend.hcl    # once per machine; set the bucket name
cp account.auto.tfvars.example account.auto.tfvars   # once per machine; set the account ID
terraform init -backend-config=backend.hcl
terraform plan
```

## Using it in an environment

Environments use the same partial configuration, with their own key:

```hcl
# envs/<env>/backend.tf
terraform {
  backend "s3" {
    key          = "<env>/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

Then `terraform init -backend-config=backend.hcl` with the bucket name in `envs/<env>/backend.hcl`.
