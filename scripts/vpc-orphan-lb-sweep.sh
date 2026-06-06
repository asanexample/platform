#!/usr/bin/env bash
# vpc-orphan-lb-sweep.sh — delete orphaned Kubernetes-created load balancers in a VPC and wait for their ENIs to
# release, so subnet/VPC deletion isn't blocked by a DependencyViolation. Wired as the networking unit's
# pre-destroy hook: by teardown time the EKS cluster (and its in-cluster cloud-controller) is already gone, so any
# k8s-tagged ELB still in the VPC is orphaned and nothing else will ever delete it — its ENIs would otherwise
# block the subnet delete (`DeleteSubnet ... DependencyViolation`, the observed networking failure). The classic
# culprit is the internal Cilium Gateway NLB (kubernetes.io/service-name: default/cilium-gateway-*).
#
# Shell hooks run with the caller's creds, so we STS assume-role into the target account (same as the unit's
# log-group cleanup hook). BEST-EFFORT: never blocks destroy — always exits 0.
#
# Usage: vpc-orphan-lb-sweep.sh <region> <role_arn> <vpc_name_tag>
set -uo pipefail

region="${1:?usage: vpc-orphan-lb-sweep.sh <region> <role_arn> <vpc_name_tag>}"
role_arn="${2:?role_arn required}"
vpc_name="${3:?vpc_name_tag required}"

# Assume the target-account role (best-effort; fall back to ambient creds if it fails).
creds=$(aws sts assume-role --role-arn "$role_arn" --role-session-name vpc-lb-sweep \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text 2>/dev/null) || true
if [ -n "${creds:-}" ] && [ "$creds" != "None" ]; then
  read -r AKI SAK ST <<<"$creds"
  export AWS_ACCESS_KEY_ID="$AKI" AWS_SECRET_ACCESS_KEY="$SAK" AWS_SESSION_TOKEN="$ST"
fi

vpc=$(aws ec2 describe-vpcs --region "$region" --filters "Name=tag:Name,Values=$vpc_name" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
if [ -z "$vpc" ] || [ "$vpc" = "None" ]; then
  echo "vpc-orphan-lb-sweep: no VPC tagged Name=$vpc_name (already gone?) — nothing to sweep"
  exit 0
fi
echo "vpc-orphan-lb-sweep: scanning VPC $vpc ($vpc_name) for orphaned k8s load balancers"

deleted=0

# ELBv2 (NLB/ALB) carrying any kubernetes.io/* tag = created by the (now-gone) cluster.
for arn in $(aws elbv2 describe-load-balancers --region "$region" \
  --query "LoadBalancers[?VpcId=='$vpc'].LoadBalancerArn" --output text 2>/dev/null); do
  ktags=$(aws elbv2 describe-tags --region "$region" --resource-arns "$arn" \
    --query "TagDescriptions[0].Tags[?starts_with(Key,'kubernetes.io/')].Key" --output text 2>/dev/null)
  if [ -n "$ktags" ]; then
    aws elbv2 delete-load-balancer --region "$region" --load-balancer-arn "$arn" 2>/dev/null \
      && { echo "vpc-orphan-lb-sweep: deleted ELBv2 $arn"; deleted=1; }
  fi
done

# Classic ELBs (belt-and-suspenders; k8s in-tree LBs can be classic too).
for name in $(aws elb describe-load-balancers --region "$region" \
  --query "LoadBalancerDescriptions[?VPCId=='$vpc'].LoadBalancerName" --output text 2>/dev/null); do
  ktags=$(aws elb describe-tags --region "$region" --load-balancer-names "$name" \
    --query "TagDescriptions[0].Tags[?starts_with(Key,'kubernetes.io/')].Key" --output text 2>/dev/null)
  if [ -n "$ktags" ]; then
    aws elb delete-load-balancer --region "$region" --load-balancer-name "$name" 2>/dev/null \
      && { echo "vpc-orphan-lb-sweep: deleted classic ELB $name"; deleted=1; }
  fi
done

if [ "$deleted" = "0" ]; then
  echo "vpc-orphan-lb-sweep: no orphaned k8s load balancers in $vpc"
  exit 0
fi

# Wait for the LB ENIs to release (they linger briefly after delete and block the subnet delete otherwise).
for _ in $(seq 1 48); do
  n=$(aws ec2 describe-network-interfaces --region "$region" \
    --filters "Name=vpc-id,Values=$vpc" "Name=description,Values=ELB*" \
    --query 'length(NetworkInterfaces)' --output text 2>/dev/null)
  if [ "$n" = "0" ] || [ -z "$n" ]; then
    echo "vpc-orphan-lb-sweep: LB ENIs released — subnets are clear to delete"
    exit 0
  fi
  echo "vpc-orphan-lb-sweep: waiting for $n LB ENIs to release..."
  sleep 5
done
echo "vpc-orphan-lb-sweep: timed out waiting for ENIs; destroy may need a --resume"
exit 0
