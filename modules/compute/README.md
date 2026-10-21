# compute

Planned: the EKS cluster and its node.

- EKS cluster `portfolio-prod`, Kubernetes version pinned by the caller (1.36). API endpoint public, limited to the admin IP allow-list, plus private access.
- Access entries for the admin user and the CI roles. No implicit cluster-creator admin.
- Managed node group `portfolio-prod-default`: 1× t4g.medium, Amazon Linux 2023 arm64, desired = min = max = 1, in a public subnet. Launch template: 20 GB gp3 encrypted, IMDSv2 required with hop limit 1. AMI release version pinned by the caller.
- EKS add-ons: `vpc-cni` (prefix delegation, max pods 30), `coredns`, `kube-proxy`, `eks-pod-identity-agent`, `metrics-server`.
- Node role (worker, ECR pull, CNI) and Pod Identity associations for the AWS Load Balancer Controller and External Secrets Operator (`ssm:GetParameter` on `/portfolio/prod/*`).

In-cluster resources are deployed by Argo CD from `k8s/`, not by this module.

Stub today: only `terraform.tf` has content. The target design is in the parent workspace `docs/`.
