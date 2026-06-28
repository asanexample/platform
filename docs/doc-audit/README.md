# Documentation Audit (2026-06-28)

A comprehensive, adversarial accuracy + completeness audit of **all non-ADR documentation**
(the ADRs were audited separately — see PR #948). Inventory only — **no edits** to the docs
themselves; corrections happen in a later pass.

**Method:** every checkable claim verified against the repo (modules, live units, scripts, CI,
`gitops/`, `cmd/`) and `CLAUDE.md`; cheap live checks where the parked clusters allow (AWS API).
Plus a dedicated **gap-hunt** pass diffing what's actually shipped (recent ADRs/commits, the live
module set, `gitops/`) against the docs to find *undocumented* features. Net is **comprehensive**:
hard errors, outdated/false claims, AND softer gaps (thin/shallow coverage, missing examples,
broken cross-links, stale versions, undocumented features).

Severity: **high** (wrong/misleading enough to cause a bad operational decision), **medium**
(stale/inaccurate, lower blast radius), **low** (cosmetic / minor / verified-correct note).

| Batch | Surface | Findings file | Status |
|-------|---------|---------------|--------|
| W1-A | docs/runbooks (1–21) | findings-runbooks-a.md | done |
| W1-B | docs/runbooks (22–42) | findings-runbooks-b.md | done |
| W1-C | docs/architecture (21) | findings-architecture.md | done |
| W1-D | docs/plans (11) + archive/compliance/examples | findings-plans.md | done |
| W1-E | docs/guides/zero-downtime + docs top-level | findings-guides-toplevel.md | done |
| W2-A | infra/modules/aws/* READMEs (22) | findings-readmes-aws.md | done |
| W2-B | observability* module READMEs (17) | findings-readmes-observability.md | done |
| W2-C | other shared module READMEs (~28) | findings-readmes-shared.md | done |
| W2-D | house skills (16) + CLAUDE.md | findings-skills-claudemd.md | done |
| W2-E | ROADMAP + REQUIREMENTS + root/infra README + infra/docs | findings-toplevel-planning.md | done |
| W3-* | GAP HUNT (undocumented shipped features) | findings-gaps.md | done |

Final synthesis: `REPORT.md` (themes, prioritized inventory, recommended fixes for the next pass).
