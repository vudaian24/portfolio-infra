# portfolio-infra

Terraform for [portfolio-web](https://github.com/vudaian24/portfolio-web), a personal portfolio site. Region `ap-southeast-1`.

**Status:** `bootstrap/` and `envs/prod` are applied. `alb_ready` and `cutover` are `true`, and `public_endpoint` is `false`: admins use the Session Manager tunnel. CI runs static checks only; the owner plans and applies from a laptop (Plan and apply). The design lives in the private workspace repo (`docs/architecture/aws-eks.md`), not here.

## What it manages

- **Network:** VPC, two public subnets, internet gateway, ALB security group (443 from Cloudflare only). No NAT gateway.
- **Cluster** (`modules/compute`): EKS 1.36 (standard support), private API endpoint only (public endpoint for `admin_cidrs` as break-glass), one managed node (t4g.medium, AL2023 arm64, 20 GB gp3, IMDSv2 hop limit 1), EKS add-ons, Pod Identity roles for the AWS Load Balancer Controller and External Secrets.
- **DNS** (`modules/dns`, Cloudflare provider v5): ACM validation records, the production hostname `portfolio`, one contact-form rate limit rule.
- **Admin access** (`modules/admin_access`, off until `admin_access_enabled = true`): Cloudflare Tunnel, Access apps and policy, and the `argocd` record for the Argo CD UI (ADR 0009). Grafana is in Grafana Cloud (ADR 0016). The site keeps the ALB.
- **Night shutdown** (`modules/night_scheduler`, `night_shutdown_enabled = true` since 2026-10-26): an EventBridge schedule and a Lambda that hold the node group at 0 between 22:00 and 08:00 ICT and all day on Sunday (`night_shutdown_off_days`, ADR 0011). The site is down for that window. Creating it does not start it; the SSM flag `/portfolio/prod/night-shutdown-enabled` does, and setting that flag to `false` stops further changes without raising a node that is already down.
- **Secrets:** SSM SecureString placeholders (`modules/secrets`). Values are set with the AWS CLI (`docs/runbooks/secrets.md`).
- **Registry and identity:** ECR `portfolio-prod-web`, GitHub OIDC role for portfolio-web (deploy), ACM certificate, AWS Budgets (140 USD).

Terraform calls only the AWS and Cloudflare APIs. It never calls the Kubernetes API. In-cluster resources are deployed by Argo CD from `portfolio-gitops`.

## Layout

```text
bootstrap/            S3 state bucket (run once per account). Its own state is in that bucket.
envs/prod/            The only environment: wiring, ACM, Budgets, ECR, the portfolio-web OIDC role
modules/network/      VPC, subnets, ALB security group
modules/compute/      EKS cluster, node group, add-ons, Pod Identity (see its README)
modules/dns/          Cloudflare records and rate limit (see its README)
modules/admin_access/ Cloudflare Tunnel and Access for Argo CD (see its README)
modules/night_scheduler/ scheduled night shutdown of the node group (see its README)
modules/secrets/      SSM SecureString placeholders
scripts/eks-tunnel.sh kubectl access through Session Manager (no IP allow-list)
.github/workflows/terraform-ci.yml   fmt, validate, TFLint, trivy (no AWS credentials)
.github/workflows/notify-workspace.yml  tells the workspace repo to record each push to main
```

## Local checks (no AWS credentials)

```sh
terraform fmt -check -recursive
for d in bootstrap envs/prod; do (cd "$d" && terraform init -backend=false -input=false && terraform validate); done
tflint --init && tflint --recursive --config "$PWD/.tflint.hcl"
trivy config --severity HIGH,CRITICAL --exit-code 1 --skip-dirs .terraform .
```

## Plan and apply (owner, laptop)

CI only checks the code; it holds no AWS role and never plans or applies. Every apply, including the first and the destroy, runs from the owner's laptop after a plan the owner has read (workspace ADR 0013). Agents never apply.

Apply only what is on `main`, so that `main` always describes what runs:

```sh
git switch main && git pull --ff-only
git status --short                         # must print nothing
aws login --region ap-southeast-1          # docs/runbooks/aws-login.md in the workspace
cd envs/prod
terraform init -backend-config=backend.hcl
terraform plan -out=prod.tfplan            # read it before applying
terraform apply prod.tfplan
rm -f prod.tfplan
```

The saved plan holds variable values, except ephemeral ones such as the Cloudflare token, and resource attributes; `*.tfplan` is git-ignored, and the file is deleted after the apply. There is no scheduled drift check: a plan that shows changes the code on `main` does not explain is drift, and is investigated before anything is applied.

### First apply of a new account

1. `bootstrap/`: create the state bucket as in `bootstrap/README.md`.
2. `envs/prod/`: set `alb_ready` and `cutover` to `false` in `terraform.tfvars`, because the ALB does not exist yet (`modules/dns/README.md`). Copy `account.auto.tfvars.example` to `account.auto.tfvars` and fill in the values. Then plan and apply as above.
3. Read the outputs `web_ci_role_arn`, `ecr_registry_host`, `cluster_name` and set the `portfolio-web` deploy settings (names in `portfolio-web/AGENTS.md`).
4. Set `node_release_version` in `terraform.tfvars` if you want to pin the node AMI (see `docs/runbooks/cluster-operations.md`).

`envs/prod` reads the Cloudflare API token from `secrets.auto.tfvars` (git-ignored). Once per laptop: `cp secrets.auto.tfvars.example secrets.auto.tfvars`, set the token, `chmod 600 secrets.auto.tfvars`. The variable `cloudflare_api_token` is `sensitive` and `ephemeral`, so the token is not written to the saved plan or the state, and `terraform apply prod.tfplan` reads the file again. Without the file, `terraform plan` prompts for `var.cloudflare_api_token`: stop it and create the file instead.

Note that a plan can list an `aws_iam_role_policy` as changed when nothing in it changed: a policy document that reads an attribute of a resource being updated is deferred to apply time, and Terraform reports the policy as in-place. Read the diff before applying rather than trusting the resource type.

## GitHub settings for portfolio-infra

The Terraform CI jobs need no secrets. Only `notify-workspace.yml` uses settings: the repository variable `WORKSPACE_SYNC_APP_CLIENT_ID` and the repository secret `WORKSPACE_SYNC_APP_PRIVATE_KEY`.

`envs/prod` reads `aws_account_id`, `budget_email`, `admin_cidrs`, `admin_principal_arn` and `access_allowed_emails` from `account.auto.tfvars` on the laptop (template: `account.auto.tfvars.example`), and `cloudflare_api_token` from `secrets.auto.tfvars` (template: `secrets.auto.tfvars.example`).

## Cloudflare checks before `alb_ready`

- SSL/TLS mode Full (strict) for the portfolio hostnames (Configuration Rule), see `modules/dns/README.md`.
- The zone has no other `http_ratelimit` ruleset. The rule resource owns the zone entry point for that phase.

## Cluster access (kubectl)

`scripts/eks-tunnel.sh` opens the EKS API on `https://127.0.0.1:8443` through a Session Manager port forwarding session from the node to the private endpoint, and switches kubectl to the context `portfolio-prod-tunnel`. Access needs `aws login` and the admin access entry, not an allow-listed IP. Run it in its own terminal; Ctrl-C closes the tunnel. Needs the AWS CLI, the Session Manager plugin (macOS: `brew install --cask session-manager-plugin`; Ubuntu: the `.deb` from AWS, see `docs/runbooks/aws-login.md` in the workspace repo) and kubectl.

- The node role has the five Session Manager actions (`modules/compute/nodes.tf`). If the node started before the role had them, the SSM Agent has given up: reboot the node.
- A session closes after 20 minutes without traffic (Session Manager default). Run the script again. If it stops at `Starting session`, press Ctrl-C and run it again.
- Break-glass, when Session Manager or the node does not work: put your IP in `admin_cidrs` (`account.auto.tfvars`), set `public_endpoint = true` in `terraform.tfvars`, and apply. Then `aws eks update-kubeconfig --region ap-southeast-1 --name portfolio-prod`. Turn it off again afterwards.
- EKS add-ons follow the default version EKS lists for the cluster version (`modules/compute/addons.tf`). When AWS changes that default, any plan shows an in-place add-on update.
- A principal that may start sessions on the node can also open a shell on it. The admin already has cluster admin rights, so this adds no real access.

## Notes

- `admin_cidrs` is used only while `public_endpoint` is true. Then it must be the same list in `account.auto.tfvars` on every machine that applies; a plan with an older list removes the other entries from the EKS allow-list.
- Destroy: from a laptop, like every apply. Follow `docs/runbooks/decommission.md`.
