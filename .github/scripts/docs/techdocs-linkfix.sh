#!/usr/bin/env bash
# techdocs-linkfix.sh — rewrite the learning portal's cross-tree Markdown links to
# absolute GitHub URLs, in place, on a *copy* of docs/learn (never the canonical tree).
#
# Why: the TechDocs site is rooted at docs/learn (docs_dir), so links that escape it
# would 404 in the built site. Two escape shapes exist and both are rewritten:
#   1. docs sibling trees — ](<../>+ {adrs|architecture|runbooks|examples}/…)
#        -> ](<repo>/blob/main/docs/{subtree}/…)
#   2. repo-root files    — ](<../>+ .claude/…)
#        -> ](<repo>/blob/main/.claude/…)
# The subtree/`.claude` name anchors the absolute path regardless of the ../ depth
# (adrs only lives at docs/adrs; .claude only at the repo root). Intra-portal
# relative links and already-absolute links are left untouched. The canonical docs
# keep their repo-relative links (which resolve natively on GitHub); only the CI
# build copy is transformed. The same transform is reused by the future
# Astro/Starlight public site.
#
# Usage:  techdocs-linkfix.sh <docs-dir>                 # e.g. build/docs/learn
#         LINKFIX_REPO_BASE=<url> techdocs-linkfix.sh …  # override the GitHub base
set -euo pipefail

TARGET="${1:?usage: techdocs-linkfix.sh <docs-dir>}"
export LINKFIX_REPO_BASE="${LINKFIX_REPO_BASE:-https://github.com/asanexample/platform/blob/main}"

[ -d "$TARGET" ] || { echo "linkfix: '$TARGET' is not a directory" >&2; exit 1; }

count=0
while IFS= read -r -d '' f; do
  perl -0pi -e 'BEGIN { $b = $ENV{LINKFIX_REPO_BASE} }
    s{\]\((?:\.\./)+(adrs|architecture|runbooks|examples)/([^)\s]+)\)}{]($b/docs/$1/$2)}g;
    s{\]\((?:\.\./)+(\.claude/[^)\s]+)\)}{]($b/$1)}g;' "$f"
  count=$((count + 1))
done < <(find "$TARGET" -name '*.md' -print0)

echo "linkfix: processed $count markdown files under $TARGET (base: $LINKFIX_REPO_BASE)"
