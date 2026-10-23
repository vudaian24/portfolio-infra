#!/usr/bin/env bash
# Opens the EKS API of portfolio-prod on https://127.0.0.1:8443 through a Session Manager
# port forwarding session on the node, then switches kubectl to the context
# portfolio-prod-tunnel. No IP allow-list is involved: access needs `aws login` (IAM) and the
# EKS access entry. Keep it running in its own terminal; Ctrl-C closes the tunnel.
#
# Needs the AWS CLI, the Session Manager plugin and kubectl.
# Usage: scripts/eks-tunnel.sh    (optional env: CLUSTER, AWS_REGION, LOCAL_PORT)
set -euo pipefail

cluster="${CLUSTER:-portfolio-prod}"
region="${AWS_REGION:-ap-southeast-1}"
port="${LOCAL_PORT:-8443}"
context="${cluster}-tunnel"

for tool in aws session-manager-plugin kubectl; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

read -r endpoint ca_data < <(aws eks describe-cluster --region "$region" --name "$cluster" \
  --query '[cluster.endpoint, cluster.certificateAuthority.data]' --output text)
host="${endpoint#https://}"

# The managed node group replaces the node on updates, so look it up on every run.
instance="$(aws ec2 describe-instances --region "$region" \
  --filters "Name=tag:eks:cluster-name,Values=$cluster" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)"
if [[ "$instance" == "None" ]]; then
  echo "no running node in $cluster" >&2
  exit 1
fi

ping="$(aws ssm describe-instance-information --region "$region" \
  --filters "Key=InstanceIds,Values=$instance" \
  --query 'InstanceInformationList[0].PingStatus' --output text)"
if [[ "$ping" != "Online" ]]; then
  echo "the node is not registered with Systems Manager (PingStatus: $ping)" >&2
  exit 1
fi

# Own cluster, user and context entries, so `aws eks update-kubeconfig` never overwrites them.
# tls-server-name keeps the certificate check against the real endpoint name.
kubectl config set-cluster "$context" --server="https://127.0.0.1:$port" --tls-server-name="$host" >/dev/null
kubectl config set "clusters.$context.certificate-authority-data" "$ca_data" >/dev/null
kubectl config set-credentials "$context" \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=aws \
  --exec-arg=eks --exec-arg=get-token \
  --exec-arg=--cluster-name --exec-arg="$cluster" \
  --exec-arg=--region --exec-arg="$region" \
  --exec-arg=--output --exec-arg=json >/dev/null
kubectl config set-context "$context" --cluster="$context" --user="$context" >/dev/null
kubectl config use-context "$context" >/dev/null

echo "kubectl context: $context (https://127.0.0.1:$port). Ctrl-C closes the tunnel."
exec aws ssm start-session --region "$region" --target "$instance" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$host\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"$port\"]}"
