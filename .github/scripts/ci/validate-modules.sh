#!/usr/bin/env bash
# Validate OpenTofu modules under infra/modules (the CI "Validate all modules" step). Each module gets a
# `tofu init -backend=false` + `tofu validate`; returns non-zero if ANY module fails init or validate.
#
# Scope:
#   - NO args  -> validate EVERY module (the full sweep; used on push-to-main).
#   - With args -> validate only the given module directories. PR scoping passes just the dirs whose files
#                  changed. Modules here are independent leaves (no module-to-module `source = "../"`
#                  references), so a change in module A can't affect module B's validation — per-module
#                  scoping is sound, and most PRs then validate 1-3 modules instead of all ~65.
#
# Parallelism: modules are independent, so init+validate fans out across the runner's cores via `xargs -P`
# (PARALLELISM, default nproc). Faster wall-clock = fewer billed runner minutes than the old serial loop.
# The shared provider cache (TF_PLUGIN_CACHE_DIR) is NOT safe to populate from many concurrent inits, so we
# pre-warm it serially with one module per provider set first; the parallel workers then only READ from it.
#
# Env in: TF_PLUGIN_CACHE_DIR (shared provider cache, created if absent). PARALLELISM (optional).
# Requires: tofu, find, grep, xargs, nproc, bash. Run from the repo root.
# NOTE: -e is intentionally omitted — failures are accumulated (per-module rc) and the build fails closed via
# the explicit `exit $FAILED`. One incidental non-zero must not abort before every module is validated.
set -uo pipefail

mkdir -p "${TF_PLUGIN_CACHE_DIR:?TF_PLUGIN_CACHE_DIR must be set}"

# Modules with known provider compatibility issues (fix separately)
SKIP_VALIDATE="infra/modules/argocd infra/modules/vcluster"

# Candidate module dirs: explicit args, else discover every module under infra/modules.
if [ "$#" -gt 0 ]; then
  REQUESTED=("$@")
else
  mapfile -t REQUESTED < <(
    find infra/modules -type f -name "*.tf" -not -path "*/.terraform/*" -exec dirname {} \; |
      sort -u | grep -v /templates
  )
fi

# Keep only real, validatable modules: has *.tf, not a /templates dir, not skip-listed.
MODULES=()
for dir in "${REQUESTED[@]}"; do
  dir="${dir%/}"
  case "$dir" in */templates | */templates/*) continue ;; esac
  compgen -G "$dir/*.tf" > /dev/null 2>&1 || { echo "Skipping $dir (no .tf files)"; continue; }
  if echo "$SKIP_VALIDATE" | grep -qw "$dir"; then echo "Skipping $dir (known issues)"; continue; fi
  MODULES+=("$dir")
done

if [ "${#MODULES[@]}" -eq 0 ]; then
  echo "No modules to validate."
  exit 0
fi
echo "Validating ${#MODULES[@]} module(s)."

# Per-module worker: init (backend-less) then validate. Grouped log + status line; rc=1 on any failure.
validate_one() {
  local dir="$1" rc=0
  echo "::group::Validating $dir"
  if tofu -chdir="$dir" init -backend=false -input=false -no-color > /dev/null 2>&1; then
    if tofu -chdir="$dir" validate -no-color; then
      echo "OK: $dir"
    else
      echo "FAIL: $dir"; rc=1
    fi
  else
    echo "FAIL (init): $dir"; rc=1
  fi
  echo "::endgroup::"
  return "$rc"
}
export -f validate_one

# Pre-warm the shared plugin cache serially (concurrent inits can corrupt it), one module per provider set,
# so the parallel fan-out only reads a populated cache. Best-effort: a warm-up failure resurfaces when that
# same module runs in the fan-out, so never fail the build here.
warm() {
  local d
  for d in "${MODULES[@]}"; do
    if [ -f "$d/versions.tf" ] && grep -q "$1" "$d/versions.tf"; then
      tofu -chdir="$d" init -backend=false -input=false -no-color > /dev/null 2>&1 || true
      return 0
    fi
  done
}
echo "Pre-warming provider cache..."
warm "hashicorp/aws"
warm "hashicorp/helm"

# Fan out across cores. xargs exits non-zero if ANY invocation fails -> FAILED.
PARALLELISM="${PARALLELISM:-$(nproc)}"
FAILED=0
printf '%s\n' "${MODULES[@]}" |
  xargs -P "$PARALLELISM" -I {} bash -c 'validate_one "$@"' _ {} || FAILED=1

exit $FAILED
