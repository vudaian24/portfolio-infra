# portfolio-infra

Terraform for [portfolio-web](https://github.com/vudaian24/portfolio-web), a personal portfolio site. Region `ap-southeast-1`.

**Status:** `bootstrap/` and `envs/prod` are applied. `alb_ready` and `cutover` are `true`, and `public_endpoint` is `false`: admins use the Session Manager tunnel. Terraform CI is on (`TF_CI_ENABLED`), so changes go through the plan and apply jobs. The design lives in the private workspace repo (`docs/architecture/aws-eks.md`), not here.

## What it manages

- **Network:** VPC, two public subnets, internet gateway, ALB security group (443 from Cloudflare only). No NAT gateway.
- **Cluster** (`modules/compute`): EKS 1.36 (standard support), private API endpoint only (public endpoint for `admin_cidrs` as break-glass), one managed node (t4g.medium, AL2023 arm64, 20 GB gp3, IMDSv2 hop limit 1), EKS add-ons, Pod Identity roles for the AWS Load Balancer Controller and External Secrets.
- **DNS** (`modules/dns`, Cloudflare provider v5): ACM validation records, the production hostname `portfolio`, one contact-form rate limit rule.
- **Secrets:** SSM SecureString placeholders (`modules/secrets`). Values are set with the AWS CLI (`docs/runbooks/secrets.md`).
- **Registry and identity:** ECR `portfolio-prod-web`, GitHub OIDC roles for portfolio-web (deploy) and portfolio-infra (plan and apply), ACM certificate, AWS Budgets (140 USD).

Terraform calls only the AWS and Cloudflare APIs. It never calls the Kubernetes API. In-cluster resources are deployed by Argo CD from `portfolio-gitops`.

## Layout

```text
bootstrap/            S3 state bucket (run once per account). Its own state is in that bucket.
envs/prod/            The only environment: wiring, ACM, Budgets, ECR, OIDC roles, Terraform CI roles
modules/network/      VPC, subnets, ALB security group
modules/compute/      EKS cluster, node group, add-ons, Pod Identity (see its README)
modules/dns/          Cloudflare records and rate limit (see its README)
modules/secrets/      SSM SecureString placeholders
scripts/eks-tunnel.sh kubectl access through Session Manager (no IP allow-list)
.github/workflows/terraform-ci.yml   fmt, validate, TFLint, trivy, plan, apply
.github/workflows/notify-workspace.yml  tells the workspace repo to record each push to main
```

## Local checks (no AWS credentials)

```sh
terraform fmt -check -recursive
for d in bootstrap envs/prod; do (cd "$d" && terraform init -backend=false -input=false && terraform validate); done
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"
trivy config --severity HIGH,CRITICAL --exit-code 1 --skip-dirs .terraform .
```

## First apply (human, laptop)

The workflow cannot assume roles that do not exist yet, so the first apply runs from a laptop with `aws login` (see `docs/runbooks/aws-login.md`).

1. `bootstrap/`: create the state bucket as in `bootstrap/README.md`.
2. `envs/prod/`: set `alb_ready` and `cutover` to `false` in `terraform.tfvars`, because the ALB does not exist yet (`modules/dns/README.md`). Copy `account.auto.tfvars.example` to `account.auto.tfvars` and fill in the values. Then `terraform init -backend-config=backend.hcl` and `terraform plan`. Apply by hand once: this creates the roles the workflow needs.
3. Read the outputs `tf_plan_role_arn`, `tf_apply_role_arn`, `web_ci_role_arn`, `ecr_registry_host`, `cluster_name` and set the GitHub settings in the next section.
4. Set `node_release_version` in `terraform.tfvars` if you want to pin the node AMI (see `docs/runbooks/cluster-operations.md`).

After that, changes go through `main`. The plan job runs on push, the apply job waits for approval in the `production` environment and applies the saved plan.

## GitHub settings for portfolio-infra

Set these in the repository settings. Values are secrets (not variables) so that the logs mask them.

| Where | Name | Value |
| --- | --- | --- |
| Repository secret | `AWS_ACCOUNT_ID` | the 12-digit account ID |
| Repository secret | `TF_STATE_BUCKET` | `portfolio-tfstate-<account>` (from `bootstrap`) |
| Repository secret | `TF_BUDGET_EMAIL` | alert email |
| Repository secret | `TF_ADMIN_PRINCIPAL_ARN` | admin role ARN |
| Repository secret | `TF_ADMIN_CIDRS` | JSON list: `[]`, or for break-glass the admin IPs, for example `["203.0.113.10/32"]` |
| Repository secret | `AWS_TF_PLAN_ROLE_ARN` | output `tf_plan_role_arn` |
| Repository secret | `CLOUDFLARE_API_TOKEN_PLAN` | read-only Cloudflare token for the zone (data lookups). Read-only because the plan job has no environment. |
| Repository variable | `TF_CI_ENABLED` | `true` turns on the plan and apply jobs; leave it unset until the CI roles exist and every secret here is set |
| Repository secret | `TF_PLAN_PASSPHRASE` | long random passphrase; the plan job encrypts the plan artifact with it (gpg, AES256) and the apply job decrypts it |
| Environment `production` secret | `AWS_TF_APPLY_ROLE_ARN` | output `tf_apply_role_arn` |
| Environment `production` secret | `CLOUDFLARE_API_TOKEN` | zone token for DNS and rulesets |
| Environment `production` | Required reviewer | the owner; deployment branches: `main` only |

`envs/prod` also needs `aws_account_id`, `tfstate_bucket_name`, `budget_email`, `admin_cidrs` and `admin_principal_arn`. CI passes them as `TF_VAR_*` from the secrets above (the plan job only; the apply job uses the saved plan).

The trust subjects are the immutable OIDC subjects (ADR 0008): `repo:vudaian24@90129616/portfolio-infra@1427185252:ref:refs/heads/main` for plan, and `...:environment:production` for apply.

## Cloudflare checks before `alb_ready`

- SSL/TLS mode Full (strict) for the portfolio hostnames (Configuration Rule), see `modules/dns/README.md`.
- The zone has no other `http_ratelimit` ruleset. The rule resource owns the zone entry point for that phase.

## Cluster access (kubectl)

`scripts/eks-tunnel.sh` opens the EKS API on `https://127.0.0.1:8443` through a Session Manager port forwarding session from the node to the private endpoint, and switches kubectl to the context `portfolio-prod-tunnel`. Access needs `aws login` and the admin access entry, not an allow-listed IP. Run it in its own terminal; Ctrl-C closes the tunnel. Needs the AWS CLI, the Session Manager plugin (`brew install --cask session-manager-plugin`) and kubectl.

- The node role has the five Session Manager actions (`modules/compute/nodes.tf`). If the node started before the role had them, the SSM Agent has given up: reboot the node.
- A session closes after 20 minutes without traffic (Session Manager default). Run the script again. If it stops at `Starting session`, press Ctrl-C and run it again.
- Break-glass, when Session Manager or the node does not work: put your IP in `admin_cidrs` (the `TF_ADMIN_CIDRS` secret and `account.auto.tfvars`), set `public_endpoint = true` in `terraform.tfvars`, and apply. Then `aws eks update-kubeconfig --region ap-southeast-1 --name portfolio-prod`. Turn it off again afterwards.
- A principal that may start sessions on the node can also open a shell on it. The admin already has cluster admin rights, so this adds no real access.

## Notes

- Public repository: the plan artifact holds variable values and resource attributes, so it is uploaded only encrypted with `TF_PLAN_PASSPHRASE` and kept one day. The plan job also masks every admin CIDR in the log, because GitHub masks a secret only as a whole string.
- The Terraform apply role cannot write IAM (roles, policies, the OIDC provider) or EKS access entries, and it can pass only the four EKS roles (cluster, node, Load Balancer Controller, External Secrets). A role that can write policies for roles it may pass is admin-equivalent. A plan that changes `aws_iam_*` or `aws_eks_access_*` resources stops in the plan job; the owner applies it from a laptop, then CI plans no IAM change. An explicit Deny on the plan and apply roles stays as a second guard.
- The apply role reads EKS update status (`eks:DescribeUpdate`, `eks:ListUpdates`), so it can wait for cluster updates such as an `admin_cidrs` change.
- `admin_cidrs` is used only while `public_endpoint` is true. Then it must be the same list in the `TF_ADMIN_CIDRS` secret and in `account.auto.tfvars` on every machine that plans locally; a local plan with an older list removes the other entries from the EKS allow-list.
- Destroy: no CI job. Follow `docs/runbooks/decommission.md`.
