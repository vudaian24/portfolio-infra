# compute

The EKS cluster `portfolio-prod` (Kubernetes 1.36) with its one managed node, EKS add-ons and the Pod Identity roles for the AWS Load Balancer Controller and External Secrets. Design: [aws-eks.md](../../../docs/architecture/aws-eks.md) (Layers, Node capacity), [ADR 0003](../../../docs/adr/0003-host-on-eks.md), [ADR 0004](../../../docs/adr/0004-terraform-single-environment.md).

## What it creates

| File | Resources |
| --- | --- |
| `main.tf` | Cluster role (`AmazonEKSClusterPolicy`), the cluster, the admin access entry with `AmazonEKSClusterAdminPolicy` |
| `nodes.tf` | Node role (`AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryPullOnly`, `AmazonEKS_CNI_Policy`), launch template, managed node group `portfolio-prod-default` |
| `addons.tf` | `vpc-cni` (prefix delegation), `kube-proxy`, `eks-pod-identity-agent`, then `coredns`, `metrics-server` |
| `pod_identity.tf` | Load Balancer Controller and External Secrets roles and Pod Identity associations |
| `policies/` | `aws-load-balancer-controller-iam-policy.json`: AWS-published policy of kubernetes-sigs/aws-load-balancer-controller tag `v3.6.1` (`docs/install/iam_policy.json`), unmodified |

## Decisions

- **Endpoint.** Public endpoint limited to `admin_cidrs`, plus private endpoint, so the node uses the VPC endpoint. CI never calls the Kubernetes API (deploy design), so CI has no access entries. The design's Layers row mentioned CI access entries; this was dropped and aws-eks.md says so.
- **Authentication.** API mode, no implicit cluster-creator admin. The only human entry is `admin_principal_arn`.
- **Support.** Standard support (no extended-support charge).
- **Bootstrap add-ons off** (`bootstrap_self_managed_addons = false`). EKS would otherwise install its own `aws-node`, `kube-proxy` and CoreDNS, which Terraform could not pin or update. Terraform creates them instead.
- **Add-on versions.** `data "aws_eks_addon_version"` without `most_recent`, so the EKS default for 1.36 is used. A plan shows a version change when AWS changes that default. To review a change first, set an explicit `addon_version` in `addons.tf`.
- **Prefix delegation.** Needed. A t4g.medium allows 17 pods without it, and the design needs 21 to 23.
- **maxPods is 110, not 30.** A managed node group without a custom AMI is capped at 110 pods, and EKS overrides any `maxPods` or `maxPodsExpression` in NodeConfig. A value of 30 needs a custom AMI in the launch template with `maxPods` set by hand, which the design does not have. The pod count is not the limit: memory requests are (aws-eks.md, Node capacity), so 110 does not change the memory budget.
- **Launch template.** No AMI, no user data, no instance type or subnet (those stay in the node group, as EKS requires). IMDSv2 required, hop limit 1, encrypted 20 GiB gp3 root (`/dev/xvda`). The AMI is `AL2023_ARM_64_STANDARD`.
- **Node release.** `node_release_version` is null by default, so EKS picks the recommended release at creation. Set it in `terraform.tfvars` after the first apply to pin it.
- **No envelope encryption.** A KMS key costs about 1 USD per month, and the design has none. Trivy AVD-AWS-0039 is ignored inline with that reason.
- **No control plane logs.** The design has no CloudWatch logs. AVD-AWS-0038 is ignored inline.
- **No subnet cluster tag.** AWS Load Balancer Controller v3 discovers public subnets from `kubernetes.io/role/elb` (set by the `network` module); the `kubernetes.io/cluster/<name>` tag is only a tie-breaker. Not added.
- **Deletion protection** is on (`deletion_protection`), so a stray destroy fails. The decommission runbook turns it off first.
- **Pod Identity.** Trust `pods.eks.amazonaws.com` with `sts:AssumeRole` and `sts:TagSession`. The Pod Identity agent add-on is required and is installed before the associations.
- **External Secrets.** `ssm:GetParameter`, `GetParameters`, `GetParametersByPath` on `${secrets_path_prefix}/*`, the three actions the Parameter Store provider uses. `kms:Decrypt` is granted for the AWS managed key `aws/ssm` only when called through SSM in this account (`kms:ViaService`, `kms:CallerAccount`). AWS managed keys take their permissions from IAM policies in the account, so the grant is needed.
- **Service accounts.** The namespaces and service account names must match `portfolio-gitops/charts/*/values.yaml` (variables `load_balancer_controller_service_account`, `external_secrets_service_account`). Changing them in gitops without changing them here breaks Pod Identity.

## Inputs with no default

`admin_cidrs`, `admin_principal_arn`, `public_subnet_ids`, `name_prefix`, `secrets_path_prefix`. Account-specific values live in `envs/prod/account.auto.tfvars` (git-ignored).

## Trivy

Ignores are inline above `aws_eks_cluster.main` (AVD-AWS-0038, 0039, 0040), each with its reason. AVD-AWS-0040 is ignored because the endpoint is public by design, and it is limited by `public_access_cidrs`, which Trivy does not evaluate.
