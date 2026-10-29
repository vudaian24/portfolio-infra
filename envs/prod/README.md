# envs/prod

The only environment, a root module. It wires the modules together and holds the few resources that connect them: ECR, the GitHub OIDC provider and the `portfolio-web` CI role, the ACM certificate, and the monthly budget. Its state is `prod/terraform.tfstate` in the bucket that `bootstrap/` creates.

How to plan and apply, and the rules around it, are in the repo `README.md` (Plan and apply). This file covers what is here and what a laptop needs before the first plan.

## Files

| File | Holds |
| --- | --- |
| `terraform.tf` | Terraform and provider versions (`aws`, `cloudflare`, `archive`) |
| `providers.tf` | The AWS provider with `allowed_account_ids` and the default tags; the Cloudflare provider with `api_token = var.cloudflare_api_token` |
| `backend.tf` | Partial S3 backend, key `prod/terraform.tfstate`; the bucket name goes in `backend.hcl` |
| `main.tf` | The module calls (`network`, `secrets`, `compute`, `night_scheduler`, `dns`, `admin_access`), ECR, the OIDC provider and the CI role, the lookup of the ALB |
| `acm.tf` | The certificate for the ALB, validated through the records of `module.dns` |
| `budgets.tf` | The monthly cost budget |
| `variables.tf`, `locals.tf`, `outputs.tf` | Inputs, names (`portfolio-prod-*`), outputs |
| `.terraform.lock.hcl` | Provider lock; commit it with provider changes |

## Laptop setup (once per machine)

Three files are git-ignored and exist only on the laptop. Copy each from its template:

| File | Template | Holds |
| --- | --- | --- |
| `backend.hcl` | `backend.hcl.example` | The state bucket name (`terraform -chdir=../../bootstrap output -raw state_bucket_name`) |
| `account.auto.tfvars` | `account.auto.tfvars.example` | `aws_account_id`, `budget_email`, `admin_cidrs`, `admin_principal_arn`, `access_allowed_emails` |
| `secrets.auto.tfvars` | `secrets.auto.tfvars.example` | `cloudflare_api_token` |

```sh
cp backend.hcl.example backend.hcl
cp account.auto.tfvars.example account.auto.tfvars
cp secrets.auto.tfvars.example secrets.auto.tfvars && chmod 600 secrets.auto.tfvars
terraform init -backend-config=backend.hcl
```

Terraform loads `terraform.tfvars` and every `*.auto.tfvars` by itself, so plan and apply need no `-var-file`.

`cloudflare_api_token` is `sensitive` and `ephemeral`: the token is not written to the saved plan or the state, and `terraform apply prod.tfplan` reads `secrets.auto.tfvars` again. Without the file, `terraform plan` prompts for `var.cloudflare_api_token`; stop it and create the file instead. The token needs the zone permissions of `modules/dns` on `anvd.io.vn`, plus the account permissions in `modules/admin_access/README.md` once `admin_access_enabled` is true.

## Switches in `terraform.tfvars`

| Variable | Now | What it does |
| --- | --- | --- |
| `alb_ready` | `true` | Looks up the ALB that the Load Balancer Controller created and passes its DNS name to `module.dns`. `false` on a new stack until the Ingress exists. |
| `cutover` | `true` | Creates the proxied `portfolio` record to the ALB. Not a rollback switch: `false` deletes the record (`modules/dns/README.md`). |
| `public_endpoint` | `false` | Break-glass: opens the public EKS API to `admin_cidrs`. Admins use `scripts/eks-tunnel.sh`. |
| `node_release_version` | pinned | EKS AMI release of the node group. A bump is a rolling update: the node is replaced by a new one. |
| `admin_access_enabled` | `false` | Argo CD through Cloudflare Access and a Tunnel (`modules/admin_access`). Needs `access_team_name` and the extra token permissions first. |
| `night_shutdown_enabled` | `true` | Creates the night scheduler. The SSM flag `/portfolio/prod/night-shutdown-enabled` starts and stops it, not this switch (`modules/night_scheduler/README.md`). |

`cluster_deletion_protection` (default `true`) is set to `false` only in the commit before the decommission destroy.

## First apply in a new account

1. `bootstrap/`: create the state bucket as in `bootstrap/README.md`.
2. Here: set `alb_ready` and `cutover` to `false` in `terraform.tfvars`, because the ALB does not exist yet (`modules/dns/README.md`). Do the laptop setup above, then plan and apply.
3. Read the outputs `web_ci_role_arn`, `ecr_registry_host` and `cluster_name`, and set the `portfolio-web` deploy settings (names in `portfolio-web/AGENTS.md`).
4. Set `node_release_version` in `terraform.tfvars` if you want to pin the node AMI (`docs/runbooks/cluster-operations.md` in the workspace).

## Outputs

`terraform output` needs only `backend.hcl` and `terraform init`, no tokens and no `account.auto.tfvars`.

- Cluster: `cluster_name`, `cluster_endpoint`, `node_group_name`, `vpc_id`, `public_subnet_ids`, `alb_security_group_id`.
- Workload roles: `load_balancer_controller_role_arn`, `external_secrets_role_arn`.
- Deploy: `ecr_registry_host`, `ecr_repository_url`, `web_ci_role_arn`, `acm_certificate_arn`.
- Night shutdown: `night_shutdown_function_name`, `night_shutdown_flag_parameter`.
- Admin access: `cloudflare_tunnel_id` (null while off), `access_aud_tags` (empty while off).

## Reading a plan

- A plan can list an `aws_iam_role_policy` as changed when nothing in it changed: a policy document that reads an attribute of a resource being updated is deferred to apply time, and Terraform reports the policy as in-place. Read the diff, not the resource type.
- `admin_cidrs` is used only while `public_endpoint` is true. Then it must be the same list in `account.auto.tfvars` on every machine that applies; a plan with an older list removes the other entries from the EKS allow-list.
- EKS add-ons follow the default version EKS lists for the cluster version (`modules/compute/addons.tf`). When AWS changes that default, any plan shows an in-place add-on update.
