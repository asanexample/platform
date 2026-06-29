---
name: maintaining-docs
description: >-
  How to keep this repo's documentation current as code changes — the same-PR discipline that
  stops docs from drifting during fast-moving feature work. Use WHENEVER you finish or ship a
  feature, add/rename/remove a module or live unit, retire or rename a mechanism or term (an auth
  model, a CRD kind, a registry, a file), flip a status (Kyverno Audit→Enforce, an ADR
  Proposed→Accepted, planned→shipped), change a CLI/policy surface, or are about to open a PR for a
  change with operator- or developer-facing impact. Covers the doc-impact map (which surfaces each
  kind of change touches), the grep-first rule for renames, the recurring drift traps, the
  update-or-flag rule, and what CI enforces automatically vs. what needs your judgment. Consult it
  as part of finishing ANY change, not only when a task explicitly mentions "docs".
---

# Maintaining Documentation

The docs here are good when written and drift only because **code changes in place and the doc
doesn't follow**. A 2026-06 audit found ~150 stale claims — almost none were "written wrong," nearly
all were "the feature moved, the doc didn't." This skill is how you stop adding to that pile.

## The core rule: docs ship in the same PR as the code

**If a change makes a doc wrong, fixing that doc is part of the change.** There is no "I'll document
it later" — *later* is exactly how every drifted doc got that way. Treat a stale doc the same as a
failing test: the PR isn't done until it's green.

## Step 1 — ask what this change touches (the doc-impact map)

Most drift happens because the author didn't know the full surface. Map your change to its surfaces:

| If your change… | Update these surfaces (same PR) |
|---|---|
| adds / removes / **renames a module** (`infra/modules/**`) | its `README.md` (**regenerate terraform-docs** — see CI below); the module inventory in `CLAUDE.md`; `infra/docs/17-available-modules.md`; a runbook/architecture doc if it's operator-facing |
| adds / changes a **live unit** (`infra/live/**`) or **deployment ordering** | the relevant `docs/runbooks/` entry; the `apply-and-destroy` / `platctl` skills; the deployment-ordering DAG in `CLAUDE.md` |
| **retires or renames a mechanism / term** (auth model, CRD kind, registry, unit, file) | **grep every doc surface** (Step 2) — this is *never* one file |
| **flips a status** (Kyverno Audit→Enforce, ADR Proposed→Accepted, planned→shipped) | the ADR `Status` line + `docs/adrs/README.md` index; `CLAUDE.md`; `ROADMAP.md` (move Now/Next → Shipped); the relevant house skill; `docs/architecture/kyverno-policy-catalog.md` for a policy |
| ships a **new user-facing capability** | `ROADMAP.md`; a `docs/runbooks/` entry if it's *operated*; a `.claude/skills/` skill if it's *authored by others*; the `docs/README.md` index; the architecture-decisions list in `CLAUDE.md` |
| changes **Kyverno policy / admission behavior** | `authoring-k8s-workloads` skill; `docs/architecture/kyverno-policy-catalog.md`; the required/mutated list in `CLAUDE.md` |
| changes a **CLI surface** (`platctl`, `scripts/`) | the `platctl` skill (command table); the relevant runbook |
| records a **new architecture decision** | follow the `authoring-adrs` skill (the ADR **and** its index) |
| changes **IAM / SCP / access** (exempt roles, OU attachments, role privileges) | `docs/architecture/aws-organizations.md`; `docs/compliance/scp-control-mapping.md`; the SCP runbooks; the IAM table in `CLAUDE.md` |

If your change isn't in the table, ask the same question anyway: *who reads a doc that just became
wrong?* Update it.

## Step 2 — grep-first for any rename or retirement

A renamed term or a retired mechanism is **always** spread across many files (the audit found single
renames touching 5–15 docs). Before you call the change done, search every doc surface for the OLD
term and reconcile each hit:

```bash
# Replace <old-term> with the thing you renamed/retired (e.g. an old CRD kind, file, auth model):
grep -rn "<old-term>" \
  docs/ .claude/skills/ CLAUDE.md README.md ROADMAP.md REQUIREMENTS.md infra/docs/ \
  $(git ls-files 'infra/modules/**/README.md')
```

Watch especially for **debug/verification steps** that reference the old thing — e.g. a runbook that
tells an operator to check an annotation or run a command that no longer exists. Those are the
highest-risk: they silently fail the one time someone needs them.

## Step 3 — the recurring drift traps (watch for these)

From the audit, the patterns that bite again and again:

- **In-place mechanism swaps.** When you change *how* something works (not just *that* it works),
  hunt for docs describing the old mechanism — including debug steps. (The audit's worst class was
  an auth migration that left runbooks telling operators to check a now-nonexistent annotation.)
- **Status flips that don't propagate.** Flipping a policy to Enforce, or an ADR to Accepted, or
  shipping a "Now/Next" roadmap item — the load-bearing maps (`CLAUDE.md`, `ROADMAP.md`, the skills)
  are the ones that get forgotten.
- **A new module invisible to the inventories.** A new module must land in its README **and**
  `CLAUDE.md` **and** `infra/docs/17-available-modules.md`. (CI now blocks the missing-README case.)
- **"Future" claims you just made true.** If you build something an ADR/doc called "not yet built,"
  "planned," or "rides the rebuild," fix that claim in the same PR — don't leave it describing a
  past that's no longer true.
- **Skills go stale too.** If your change touches a domain a house skill covers, the skill is a doc
  — update it. (Use `skill-self-correction` when a skill misleads you.)
- **terraform-docs not regenerated.** Any change to a module's variables/outputs/resources requires
  re-running terraform-docs on that module (CI enforces this on the modules you touched).

## Step 4 — when you can't fully fix it: flag, don't drift

Fast work sometimes can't carry a deep doc rewrite in the same PR. The rule is **never silently
leave a doc wrong**:

1. **Update the load-bearing surfaces inline** — the inventories, status lines, and any
   debug/command step that would now fail. These are cheap and high-impact.
2. **For a deeper rewrite**, leave a dated, specific note in the doc (`> **NOTE (YYYY-MM-DD):** X
   changed to Y; this section needs a rewrite — <issue>`) **and** open a tracking issue.

The forbidden third option is doing nothing.

## What CI enforces vs. what's on you

**CI (deterministic — see `.github/workflows/ci.yml`, the `doc-currency` job):**

- **Every module has a `README.md`** — a new module with no README fails the build.
- **terraform-docs is fresh on the modules your PR changed** — touch a module's `.tf`/chart and its
  README's generated block must be regenerated (`terraform-docs -c .terraform-docs.yml <module>`).
- Markdown lints (the existing `markdown-lint` job).

**You (judgment — CI can't check these):** everything in the doc-impact map — runbooks, architecture
docs, the `CLAUDE.md` inventory/status/DAG, `ROADMAP.md`, the house skills, the `docs/README.md`
index, and ADR status. The CI backstops catch the mechanical drift; the map is what keeps the prose
true.

## Quick checklist (run before opening a PR)

- [ ] Did I add/rename/remove a module? → README regenerated (`terraform-docs`), and added to
      `CLAUDE.md` + `infra/docs/17-available-modules.md`.
- [ ] Did I rename or retire a term/mechanism/file? → grepped every doc surface (Step 2) and
      reconciled each hit, including debug/verify steps.
- [ ] Did I flip a status or ship a roadmap item? → ADR Status + index, `CLAUDE.md`, `ROADMAP.md`,
      and the relevant skill updated.
- [ ] Did I make a "future"/"planned"/"not yet built" claim become true? → that doc fixed.
- [ ] Did I touch a domain a house skill covers? → skill updated.
- [ ] Anything I couldn't fully fix? → dated note + tracking issue, not silence.
