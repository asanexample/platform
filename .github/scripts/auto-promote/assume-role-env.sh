#!/usr/bin/env bash
# Assume an IAM role and emit eval-able `export AWS_*` lines for the resulting temporary credentials, so a workflow
# step can run subsequent AWS/kubectl calls as that role. De-duplicates the assume-role dance the auto-promote
# job needs twice (read the promote-App secret; then read ArgoCD health via PlatformDeployer's EKS access entry).
#
# Usage (inside a step, NOT across steps — env doesn't persist between run: blocks):
#   creds_env="$(.github/scripts/auto-promote/assume-role-env.sh "$ROLE_ARN" my-session)"
#   eval "$creds_env"
# Splitting assign-then-eval (not `eval "$(...)"`) lets `set -e` fail the step if the assume-role fails, instead
# of silently eval-ing an empty string.
#
# Requires: aws, jq.
set -euo pipefail

arn="${1:?usage: assume-role-env.sh <role-arn> <session-name>}"
session="${2:?usage: assume-role-env.sh <role-arn> <session-name>}"

creds="$(aws sts assume-role --role-arn "$arn" --role-session-name "$session" --query Credentials --output json)"
printf 'export AWS_ACCESS_KEY_ID=%q\n'     "$(jq -r .AccessKeyId     <<<"$creds")"
printf 'export AWS_SECRET_ACCESS_KEY=%q\n' "$(jq -r .SecretAccessKey <<<"$creds")"
printf 'export AWS_SESSION_TOKEN=%q\n'     "$(jq -r .SessionToken    <<<"$creds")"
