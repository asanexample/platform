#!/usr/bin/env bash
set -euo pipefail

# Tunnel kubectl to a private EKS cluster via SSM Session Manager.
#
# Usage:
#   ./scripts/eks-tunnel.sh <cluster-name> <region> [instance-id]
#
# If instance-id is omitted, discovers the SSM bastion automatically by tag.
# Once running, configure kubectl with:
#   aws eks update-kubeconfig --name <cluster-name> --region <region>
#   # Then edit ~/.kube/config to change the server to https://localhost:8443

CLUSTER_NAME="${1:?Usage: $0 <cluster-name> <region> [instance-id]}"
REGION="${2:?Usage: $0 <cluster-name> <region> [instance-id]}"
INSTANCE_ID="${3:-}"
LOCAL_PORT="${EKS_TUNNEL_PORT:-8443}"

if [ -z "$INSTANCE_ID" ]; then
  echo "Discovering SSM bastion instance..."
  INSTANCE_ID=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters \
      "Name=tag:Name,Values=*ssm-bastion*" \
      "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

  if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo "Error: no running SSM bastion instance found" >&2
    exit 1
  fi
fi

EKS_ENDPOINT=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.endpoint" \
  --output text)

EKS_HOST="${EKS_ENDPOINT#https://}"

CALLER_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

CLUSTER_ARN=$(aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.arn" \
  --output text)

CLUSTER_ACCOUNT_ID=$(echo "$CLUSTER_ARN" | cut -d: -f5)

UPDATE_ARGS="--name $CLUSTER_NAME --region $REGION --role-arn arn:aws:iam::${CLUSTER_ACCOUNT_ID}:role/PlatformAdmin"

aws eks update-kubeconfig $UPDATE_ARGS
kubectl config set-cluster "$CLUSTER_ARN" \
  --server="https://localhost:${LOCAL_PORT}" \
  --tls-server-name="$EKS_HOST" 2>/dev/null

echo "Cluster:  $CLUSTER_NAME"
echo "Endpoint: $EKS_HOST"
echo "Instance: $INSTANCE_ID"
echo "Tunnel:   localhost:$LOCAL_PORT -> $EKS_HOST:443"
echo ""
echo "kubeconfig updated — kubectl is ready to use in another terminal."
echo "Press Ctrl+C to close the tunnel."

aws ssm start-session \
  --region "$REGION" \
  --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$EKS_HOST\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
