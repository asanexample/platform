---
name: authoring-adrs
description: >-
  How to write and evolve Architecture Decision Records in this repo (docs/adrs/). Use when
  recording a new architecture decision, editing an existing ADR, or deciding whether a change
  warrants a NEW ADR versus an in-place amendment. Covers the file naming/numbering, the
  required section structure, the Proposed/Accepted/Superseded lifecycle, the index that must
  be kept in sync, and the house rule for amend-in-place vs new-ADR. Use it whenever a task
  mentions an ADR or "architecture decision" so the new record matches house conventions.
---

# Authoring ADRs

ADRs live in **`docs/adrs/`** and are the decision record for the platform. They're
append-friendly and human-reviewed. Source of truth: the existing ADRs and
`docs/adrs/README.md` (the canonical index). There's no template file — the structure below is
the convention every ADR follows.

## File naming & numbering

- Path: `docs/adrs/NNN-kebab-case-title.md` — **zero-padded 3-digit** number.
- **Sequential and monotonic.** Next number = current max + 1. Find it with:

```bash
ls -1 docs/adrs/ | grep -E '^[0-9]{3}-' | sort | tail -1
```

- No reservation step — claim the next number, and the PR review cross-checks against the index.

## Structure

```markdown
# ADR-NNN: <Title>

**Date:** YYYY-MM-DD

**Status:** Proposed | Accepted | Superseded

## Context
Problem, constraints, forces, background.

## Decision
The chosen approach (often numbered design points D1, D2, …).

## Consequences
### Positive
### Negative
### Risks

## Alternatives considered   (if not folded into Context)

## Related   (optional; real ADRs vary — "Related", "Related ADRs", "Relationships", or omitted)
Links to related ADRs / PRs / issues, e.g. [ADR-067](067-idp-domain-model.md).
```

Match the casing real ADRs use — section headings like `## Alternatives considered` are
lowercase after the first word. Context / Decision / Consequences are the consistent spine;
the trailing sections (Alternatives, Related, Scope/Follow-Up) are optional and their naming
varies, so follow a nearby recent ADR rather than treating this template as rigid.

Reference other ADRs as `[ADR-NNN](NNN-kebab-title.md)`; in commits use `docs(adr-NNN): …`.

## Status lifecycle

- **Proposed** — direction agreed, not yet built / rebuild-gated.
- **Accepted** — in force, being built or used.
- **Superseded** — replaced by a later ADR. Record it three ways: set the status line
  (`Superseded by ADR-053/059`), add a short retained-as-history note at the top, and have the
  superseding ADR cite what it replaces (`Supersedes the … parts of [ADR-049]`).

## The house rule: amend in place vs. new ADR

This is the convention to get right (it's a standing piece of feedback):

- **Amend in place** when refining an *unimplemented* part of an existing decision — add a dated
  amendment block at the top (`> Amendment (YYYY-MM-DD, #PR): …`) citing the PR. Don't spawn a
  "refines ADR-NNN" record for something not yet built.
- **Write a NEW ADR** only for an *evolving BUILT decision* or a *distinct domain* — a new axis,
  a new model, a new governance boundary, or a decision to defer/halt a feature.

## Record the as-built outcome (when a Proposed ADR ships)

When a *Proposed* ADR is actually built, do two things: flip the status to **Accepted**, and add a dated
section recording what *shipping* taught you. `## Consequences` are predicted at decision time; the build
surfaces the real thing — the integration gotchas the next person will hit, refinements to the plan, and
sometimes an outright **correction** of an assumption the ADR made. Capture: what shipped beyond the core
decision, the durable gotchas, any refinement/correction, and remaining follow-ups (cite the epic/PRs and
date it). Recording a *correction* is the highest-value part — it's how the decision record stays
trustworthy instead of quietly diverging from reality.

Like the other trailing sections, the exact heading varies — **follow a recent exemplar rather than coining
a fifth**: `## Implementation notes (as-built)` ([ADR-078](078-cluster-elasticity-karpenter.md)) or
`## Implementation status & learnings` ([ADR-082](082-platform-agent-runtime-xagent.md)). (Older ADRs drifted
to "Implementation Status"/"Implementation outline" — don't add new variants.)

## Keep the index in sync

`docs/adrs/README.md` is the canonical, hand-maintained list grouped by domain. **Adding an ADR
means adding a row** (link + one-line + status) to the correct section; superseding one means
updating its row. This is part of the change, not a follow-up.

## References

- `docs/adrs/README.md` — the canonical index (keep in sync)
- Recent exemplars: `docs/adrs/088-*.md` (latest), `docs/adrs/082-*.md`, `docs/adrs/067-*.md`, `docs/adrs/053-*.md` (amendment style)
