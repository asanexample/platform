#!/usr/bin/env bash
# Shared library for bootstrap and teardown scripts.

set -euo pipefail

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

check_prerequisites() {
  local missing=()
  for tool in tofu terragrunt aws kubectl jq; do
    command -v "$tool" &>/dev/null || missing+=("$tool")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required tools: ${missing[*]}"
    exit 1
  fi

  local account_id
  account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || { log_error "AWS credentials not configured. Run: aws sso login"; exit 1; }
  log_info "AWS account: $account_id"

  if ! secret_exists "platform/cloudflare/api-token" platform; then
    log_error "Cloudflare API token not found in Secrets Manager (platform/cloudflare/api-token)."
    log_error "Create it with: aws secretsmanager create-secret --name platform/cloudflare/api-token --secret-string '<TOKEN>' --region us-east-1 --profile platform"
    exit 1
  fi
}

# SCP-protected resource types that cannot be deleted by member accounts.
readonly SCP_PROTECTED_TYPES="aws_kms_key|aws_kms_alias|aws_flow_log"

# run_tg <dir> [apply|destroy] [extra-args...]
#   Runs terragrunt in the given directory. Defaults to 'apply' with -auto-approve.
#   On destroy, if an SCP blocks deletion, removes the protected resources from
#   state and retries automatically.
run_tg() {
  local dir="$1"; shift
  local action="apply"
  case "${1:-}" in
    apply|destroy) action="$1"; shift ;;
  esac
  local unit_name
  unit_name=$(basename "$dir")

  log_info "  → $unit_name ($action)"
  local logfile
  logfile=$(mktemp "/tmp/tg-${unit_name}-${action}-XXXXXX.log")

  if (cd "$dir" && terragrunt "$action" -auto-approve "$@" > "$logfile" 2>&1); then
    rm -f "$logfile"
    return 0
  fi

  if [[ "$action" == "destroy" ]] && grep -q "service.control.policy\|service_control_policy" "$logfile"; then
    log_warn "  SCP blocked deletion in $unit_name — removing protected resources from state..."
    _remove_scp_protected_resources "$dir"

    if (cd "$dir" && terragrunt destroy -auto-approve > "$logfile" 2>&1); then
      rm -f "$logfile"
      return 0
    fi
  fi

  cat "$logfile"
  log_error "Failed: $unit_name ($action) (see $logfile)"
  exit 1
}

# _remove_scp_protected_resources <dir>
#   Lists state and removes any resources matching SCP-protected types.
_remove_scp_protected_resources() {
  local dir="$1"
  local resources
  resources=$(cd "$dir" && terragrunt state list 2>/dev/null | grep -E "$SCP_PROTECTED_TYPES" || true)

  if [[ -z "$resources" ]]; then
    return 0
  fi

  while IFS= read -r resource; do
    log_warn "    Removing $resource from state (SCP-protected)"
    (cd "$dir" && terragrunt state rm "$resource" >/dev/null 2>&1) || true
  done <<< "$resources"
}

# run_tg_parallel <dir1> <dir2> ...
#   Runs terragrunt apply -auto-approve in each directory concurrently.
run_tg_parallel() {
  local pids=() names=() logs=()
  for dir in "$@"; do
    local name
    name=$(basename "$dir")
    local logfile
    logfile=$(mktemp "/tmp/tg-${name}-XXXXXX.log")
    names+=("$name")
    logs+=("$logfile")
    (cd "$dir" && terragrunt apply -auto-approve > "$logfile" 2>&1) &
    pids+=($!)
  done

  local failed=0
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
      log_success "  ✓ ${names[$i]}"
    else
      log_error "  ✗ ${names[$i]} (see ${logs[$i]})"
      failed=1
    fi
  done
  [[ $failed -eq 0 ]] || exit 1
}

# run_tg_destroy_parallel <dir1> <dir2> ...
#   Runs terragrunt destroy -auto-approve in each directory concurrently.
#   On SCP failures, removes protected resources from state and retries.
run_tg_destroy_parallel() {
  local dirs=("$@")
  local pids=() names=() logs=()
  for dir in "${dirs[@]}"; do
    local name
    name=$(basename "$dir")
    local logfile
    logfile=$(mktemp "/tmp/tg-${name}-destroy-XXXXXX.log")
    names+=("$name")
    logs+=("$logfile")
    (cd "$dir" && terragrunt destroy -auto-approve > "$logfile" 2>&1) &
    pids+=($!)
  done

  local failed=() failed_dirs=()
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
      log_success "  ✓ ${names[$i]} (destroyed)"
    elif grep -q "service.control.policy\|service_control_policy" "${logs[$i]}"; then
      log_warn "  ⚠ ${names[$i]} hit SCP — will retry"
      failed+=("$i")
      failed_dirs+=("${dirs[$i]}")
    else
      log_error "  ✗ ${names[$i]} (see ${logs[$i]})"
      exit 1
    fi
  done

  for i in "${!failed_dirs[@]}"; do
    local dir="${failed_dirs[$i]}"
    local name
    name=$(basename "$dir")
    _remove_scp_protected_resources "$dir"
    log_info "  → $name (retry destroy)"
    if ! (cd "$dir" && terragrunt destroy -auto-approve > /dev/null 2>&1); then
      log_error "  ✗ $name (retry failed)"
      exit 1
    fi
    log_success "  ✓ $name (destroyed)"
  done
}

# prompt_manual_step <title>
#   Reads a heredoc from stdin, prints it in a bordered box, waits for Enter.
prompt_manual_step() {
  local title="$1"
  local body
  body=$(cat)

  echo ""
  echo "┌──────────────────────────────────────────────────────────────┐"
  echo "│  MANUAL STEP: $title"
  echo "├──────────────────────────────────────────────────────────────┤"
  while IFS= read -r line; do
    printf "│  %s\n" "$line"
  done <<< "$body"
  echo "└──────────────────────────────────────────────────────────────┘"
  echo ""
  read -r -p "Press Enter when done..."
}

# validate_secret <secret-id> [profile]
#   Checks that an AWS Secrets Manager secret exists.
validate_secret() {
  local secret_id="$1"
  local profile_args=()
  [[ -n "${2:-}" ]] && profile_args=(--profile "$2")
  if ! aws secretsmanager describe-secret --secret-id "$secret_id" \
       --region us-east-1 "${profile_args[@]}" --query 'Name' --output text &>/dev/null; then
    log_error "Secret '$secret_id' not found in Secrets Manager."
    exit 1
  fi
  log_success "  Secret '$secret_id' exists."
}

# secret_exists <secret-id> [profile]
#   Returns 0 if the secret exists, 1 otherwise.
secret_exists() {
  local profile_args=()
  [[ -n "${2:-}" ]] && profile_args=(--profile "$2")
  aws secretsmanager describe-secret --secret-id "$1" \
    --region us-east-1 "${profile_args[@]}" --query 'Name' --output text &>/dev/null
}

# eks_cluster_exists <cluster-name> <region>
#   Returns 0 if the EKS cluster exists, 1 otherwise.
eks_cluster_exists() {
  aws eks describe-cluster --name "$1" --region "$2" \
    --query 'cluster.name' --output text &>/dev/null 2>&1
}

# eks_endpoint_is_public <cluster-name> <region>
#   Returns 0 if the EKS public endpoint is enabled.
eks_endpoint_is_public() {
  local val
  val=$(aws eks describe-cluster --name "$1" --region "$2" \
    --query 'cluster.resourcesVpcConfig.endpointPublicAccess' --output text 2>/dev/null)
  [[ "$val" == "True" ]]
}

# eks_endpoint_is_private_only <cluster-name> <region>
#   Returns 0 if public access is disabled (private-only).
eks_endpoint_is_private_only() {
  local val
  val=$(aws eks describe-cluster --name "$1" --region "$2" \
    --query 'cluster.resourcesVpcConfig.endpointPublicAccess' --output text 2>/dev/null)
  [[ "$val" == "False" ]]
}

# wait_for_eks_deletion <cluster-name> <region> [timeout-seconds]
#   Polls until the EKS cluster no longer exists. Default timeout: 15 minutes.
wait_for_eks_deletion() {
  local cluster="$1" region="$2" timeout="${3:-900}"
  local elapsed=0 interval=30

  if ! eks_cluster_exists "$cluster" "$region"; then
    log_success "  Cluster $cluster already gone."
    return 0
  fi

  log_info "  Waiting for EKS cluster $cluster to be deleted (timeout: ${timeout}s)..."
  while eks_cluster_exists "$cluster" "$region"; do
    if [[ $elapsed -ge $timeout ]]; then
      log_error "Timed out waiting for cluster $cluster deletion after ${timeout}s."
      exit 1
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
    log_info "  Still waiting... (${elapsed}s elapsed)"
  done
  log_success "  Cluster $cluster deleted."
}

# k8s_crd_exists <crd-name>
#   Returns 0 if the CRD is registered in the cluster.
k8s_crd_exists() {
  kubectl get crd "$1" --request-timeout=5s &>/dev/null 2>&1
}
