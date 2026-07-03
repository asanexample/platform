---
name: triaging-issues
description: >-
  How to keep the GitHub issue board current and honest — the reconciliation discipline that stops
  the board from drifting behind the code. Use WHENEVER you're asked to triage issues, "bring the
  board up to date", close out completed work, audit/clean up issues, check whether an issue is
  still real, label or re-label issues, or reconcile the board after a burst of merges — and also
  proactively when you finish shipping something that a tracking issue describes. Covers why the
  board drifts (PRs cite issues in titles but rarely use `Closes #`), verifying status against
  PRIMARY SOURCES rather than the issue body / ROADMAP / memory, the origin/main-vs-worktree trap
  that produces false "not built" verdicts, how to fan out verification with subagents, the
  close/keep-open/relabel decision rules, epic and partial-completion handling, and the exact `gh`
  commands (with the flag gotchas). Consult it any time a task touches issue status, not only when
  someone says the word "triage".
---

# Triaging issues — keeping the board current

The board is the system of record for live status (`ROADMAP.md` is the narrative map; the two are
kept in step — see [[maintaining-docs]]). It drifts for one structural reason worth internalizing:

> **PRs reference issues in their *title* (`feat(x): … (#590)`) but almost never use a `Closes #590`
> trailer.** GitHub only auto-closes on a `Closes/Fixes` keyword merged to the default branch, so the
> work ships and the issue silently stays open. Multiply by a fast merge cadence and the board is
> weeks behind within a sprint.

So triage is not "read the issues and guess." It is **reconciliation**: for each open issue, decide
its true state from primary sources, then make the board reflect that. Guessing from the issue body,
the roadmap, or memory just launders stale claims — those are lagging indicators, not evidence.

## The one rule: verify against primary sources

Rank your evidence. Trust the top of this list; treat the bottom as *leads to verify*, never as truth:

1. **The code on `origin/main`** — the module/manifest/workflow actually implements (or doesn't) the thing.
2. **Merged PRs** — `gh pr list --state merged`, especially titles/bodies citing the issue number.
3. **ADR status** — `Proposed` vs `Accepted` vs `Superseded` in `docs/adrs/`; git history (`git log --grep`).
4. **The issue's own body / checklist** — often stale; a lead, not proof.
5. **`ROADMAP.md` and memory** — narrative; frequently behind the code. Never close on these alone.

An issue is **closeable only when it is BUILT + LIVE** with concrete evidence (a PR number, a file
path, an ADR flipped to Accepted). Distinguish carefully — most drift hides in these:

- **BUILT + LIVE** → close.
- **DESIGNED** (ADR written, XRD field reserved, code stubbed/inert) → keep open.
- **PARTIAL** (core shipped, a slice remains) → close the done slice only if it's a separable issue; otherwise keep open with a status comment.
- **DEFERRED / not-started** → keep open; make sure the `deferred` label reflects it.

## ⚠️ The trap that will bite you: a stale checkout

You are frequently working in a **worktree that is behind `origin/main`**. If you (or a subagent)
grep that checkout, a feature that shipped yesterday reads as "not built" — a false negative that
leads you to keep a done issue open, or worse, to comment "still missing X" on something that exists.
This is the single most common way triage goes wrong here.

**Before trusting any "not built" conclusion, reconcile with `origin/main`:**

```bash
git fetch origin main -q
git rev-list --count HEAD..origin/main          # how far behind am I?
git log HEAD..origin/main --oneline             # what shipped that I can't see?
git log HEAD..origin/main --format='%s' | grep -oE '#[0-9]+' | sort -u   # issues those commits touch
```

Then verify specific facts against main directly, not the working tree:

```bash
git show origin/main:path/to/file.tf | grep -n 'thing'
git cat-file -e origin/main:path/to/new-file && echo exists
```

Two more time-based gotchas in the same family:

- **A fix may have been reverted.** A merged PR is not proof it stuck — grep for a follow-up revert
  (`git log --oneline --grep=revert`; e.g. a fix in `#830` undone by `#831`). The capability is *not* live.
- **Things land mid-triage.** On a long sweep, re-check an issue's state *immediately before* you act
  (`gh issue view N --json state`). A backup you were about to flag as missing may have merged an hour ago.

## Workflow

### 1. Snapshot and gather signal (cheap, do it once, up front)

```bash
gh issue list --state open --limit 500 \
  --json number,title,labels,body,milestone > open_issues.json
gh pr list --state merged --limit 200 \
  --json number,title,closingIssuesReferences,mergedAt > merged_prs.json
gh label list --limit 200                    # know the label vocabulary before you relabel
```

Cross-reference open issues to merged-PR titles by issue number (a quick script beats eyeballing).
Expect most matches to be *title mentions with no `closes` link* — that's the drift, and each is a
"did this actually ship?" question to answer from the code.

### 2. Verify — fan out for a big board

For anything beyond ~15 issues, parallelize. Cluster the open issues by area (observability,
identity, policy, control-plane, network, tech-debt, …) and give each cluster to a subagent with a
tight brief: *verify each issue's true state against the codebase / ADRs / git / merged PRs — NOT the
roadmap or memory — and return a per-issue verdict (CLOSE with evidence / KEEP-OPEN with a one-line
status + what's left / RELABEL / UNSURE) with citations.* Hand them the `open_issues.json` and
`merged_prs.json` paths so they don't re-fetch. Have them classify BUILT-LIVE vs DESIGNED vs PARTIAL
vs DEFERRED explicitly — that distinction is where the judgment lives.

Collect verdicts into one findings file before acting, so cross-references — dedupes and
"residual-tracked-by" pointers — resolve against the full picture.

### 3. Act — closes, labels, comments

Apply the decision rules below. Batch the `gh` calls. Leave a short evidence trail on every close so
a reader (or future you) can see *why*, not just *that*, it closed.

### 4. Keep the roadmap in step, then report

Reflect the same verified reality in `ROADMAP.md` (see [[maintaining-docs]] — move shipped items to
Shipped, correct stale status). Then write a report: what closed (with evidence), what got relabeled,
what status comments went out, and what you intentionally left open and why.

## Decision rules

**Close** — only BUILT+LIVE, with evidence. Close as *completed* (the default) and attach a comment
citing the PR/file/ADR. A close without evidence is indistinguishable from guessing:

```bash
gh issue close 817 --reason completed \
  -c "Fixed (TD2-14). Composition emits a per-service ECR LifecyclePolicy (composition.yaml, #829): untagged expire 7d, keep last 100."
```

**Epics** — an umbrella closes only when *every* child is done. If the core shipped but deferred
phases remain, keep it open and post a status comment listing what's done vs. what carries on (which
child issues). Don't close an epic just because its headline capability exists.

**Partial completion** — when a separable slice is done, close *that* issue but point the remainder at
a live tracking issue, and **verify that issue is actually open** so the work isn't orphaned:

```bash
gh issue close 594 -c "Epic complete — all six add-on modules on Pod Identity. EBS CSI remainder tracked in #680."
gh issue view 680 --json state --jq .state    # must be OPEN
```

**Duplicates** — close one into the other with a pointer (`Closing as a duplicate of #928 — same root
cause; the unpark path is handled by #1105, the general failover case is #928`). Keep the better-scoped
one open.

**Relabel** — every issue should carry an `area/*` and a type (`bug`/`enhancement`/`tech-debt`/…);
add `deferred`/`blocked`/`epic`/`priority: top` where they apply. Catch **fully-unlabeled** issues —
whole epics land with no labels. Use `--add-label`/`--remove-label`; multiple labels are comma-separated:

```bash
gh issue edit 105 --add-label "area/control-plane,enhancement" --remove-label "area/data-services"
```

**Editing bodies/titles** — prefer a **dated status comment** over rewriting a body; it's non-destructive
and preserves history. Retitle only when the title is now factually *wrong* (e.g. "Backstage **and**
Keycloak DBs have no backup" once Backstage's landed → narrow to Keycloak). When a body's checklist is
stale, say so in the comment rather than silently editing someone's checkboxes.

**Keep-open is a valid, common outcome.** Most of a mature board is legitimately-open deferred/design
work. Don't manufacture closes to look productive — a wrong close erodes trust in the board more than
an honestly-open issue does.

## `gh` command cheat-sheet (and the flag gotcha)

| Action | Command |
|---|---|
| List open w/ detail | `gh issue list --state open --limit 500 --json number,title,labels,body` |
| Merged PRs + close refs | `gh pr list --state merged --limit 200 --json number,title,closingIssuesReferences` |
| Close with evidence | `gh issue close <n> --reason completed -c "…"` |
| Comment | `gh issue comment <n> -b "…"` |
| Add/remove labels | `gh issue edit <n> --add-label "a,b" --remove-label "c"` |
| Retitle | `gh issue edit <n> --title "…"` |
| Check state before acting | `gh issue view <n> --json state,stateReason,closedAt` |

**Gotcha:** `gh issue close` takes the comment flag as `-c`, but `gh issue comment` uses **`-b`**
(`--body`), *not* `-c`. Mixing them fails the whole batch — a real papercut on long sweeps.

## The durable fix (mention it, don't rely on it)

Manual triage is the mop; the leak is PRs that ship work without a `Closes #`. When you touch a PR
that finishes an issue, add a `Closes #N` trailer to the **body** so it auto-closes on merge. A
recurring triage (e.g. a scheduled agent) catches what slips through, but the cheapest board-currency
is closing at merge time. If drift is chronic, a CI check that flags a PR whose title cites `#N`
without a `Closes/Fixes` trailer is worth proposing.
