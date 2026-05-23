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

  if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    log_error "CLOUDFLARE_API_TOKEN is not set. Export it before running."
    exit 1
  fi
}

# run_tg <dir> [apply|destroy] [extra-args...]
#   Runs terragrunt in the given directory. Defaults to 'apply' with -auto-approve.
run_tg() {
  local dir="$1"; shift
  local action="apply"
  case "${1:-}" in
    apply|destroy) action="$1"; shift ;;
  esac
  local unit_name
  unit_name=$(basename "$dir")

  log_info "  → $unit_name ($action)"
  if ! (cd "$dir" && terragrunt "$action" -auto-approve "$@"); then
    log_error "Failed: $unit_name ($action)"
    exit 1
  fi
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
run_tg_destroy_parallel() {
  local pids=() names=() logs=()
  for dir in "$@"; do
    local name
    name=$(basename "$dir")
    local logfile
    logfile=$(mktemp "/tmp/tg-${name}-destroy-XXXXXX.log")
    names+=("$name")
    logs+=("$logfile")
    (cd "$dir" && terragrunt destroy -auto-approve > "$logfile" 2>&1) &
    pids+=($!)
  done

  local failed=0
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}"; then
      log_success "  ✓ ${names[$i]} (destroyed)"
    else
      log_error "  ✗ ${names[$i]} (see ${logs[$i]})"
      failed=1
    fi
  done
  [[ $failed -eq 0 ]] || exit 1
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

# validate_secret <secret-id>
#   Checks that an AWS Secrets Manager secret exists.
validate_secret() {
  local secret_id="$1"
  if ! aws secretsmanager describe-secret --secret-id "$secret_id" \
       --region us-east-1 --query 'Name' --output text &>/dev/null; then
    log_error "Secret '$secret_id' not found in Secrets Manager."
    exit 1
  fi
  log_success "  Secret '$secret_id' exists."
}

# secret_exists <secret-id>
#   Returns 0 if the secret exists, 1 otherwise.
secret_exists() {
  aws secretsmanager describe-secret --secret-id "$1" \
    --region us-east-1 --query 'Name' --output text &>/dev/null
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

# k8s_crd_exists <crd-name>
#   Returns 0 if the CRD is registered in the cluster.
k8s_crd_exists() {
  kubectl get crd "$1" --request-timeout=5s &>/dev/null 2>&1
}
