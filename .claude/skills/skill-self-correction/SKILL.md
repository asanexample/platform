---
name: skill-self-correction
description: >-
  How to durably fix a HOUSE SKILL (under .claude/skills/) when it misleads you during a task —
  so the skills keep improving instead of silently drifting. Use it the moment you notice a
  house skill is wrong, stale, or incomplete: a command it gave you ERRORED (wrong/renamed flag,
  denied operation), a fact it ASSERTED is contradicted by primary source (a binary's --help, the
  real module/manifest/HCL, the live cluster, CI, a runbook), it led you to a wrong ASSUMPTION
  that bit you, or you just fixed a bug a skill should have prevented. Don't just work around it —
  verify the correct fact and fix the skill via a PR. For building or trigger-optimizing a skill
  from scratch, use skill-creator instead.
---

# Self-correcting house skills

The house skills under `.claude/skills/` are point-in-time snapshots — the repo drifts, and a
skill can be inaccurate or *invite a wrong assumption*. When one misleads you mid-task, the high-
leverage move is to durably fix it so no agent hits the same thing again. This is the in-the-field
correction loop; for authoring a new skill or tuning its triggering, use `skill-creator`.

**"Auto-correct" means proactive, not unsupervised.** Verification is the safeguard, not the edit:
a confidently-wrong "fix" makes the skill *more* wrong and ships that to every agent. Always verify
against source, then land the fix as a focused, reviewable PR — never a silent rewrite.

## When this fires

- You followed a skill and a **command it gave errored** (wrong flag, renamed command, denied op).
- A skill **asserted a fact** that primary source contradicts.
- A skill led you to a **wrong assumption** that bit you (assumed a permission/behavior that turned
  out denied or different).
- You just **fixed a bug a skill should have prevented** or warned about.

## The loop

1. **Is it the skill, or your misuse of it?** Re-READ the skill's actual current text — don't
   trust your memory of what it said. Then separate two cases:
   - the skill **states X and X is wrong/stale** → fix the skill; or
   - the skill was **right and you over-extended it** → fix your understanding, *and* judge whether
     the skill's framing *invited* the leap. If it did, tighten it so the next agent won't repeat it.

   > Real example: `cluster-access` said PlatformAdmin can "delete a stuck pod" (accurate), but the
   > loose "read + operate" framing invited the wrong assumption it could delete a *Job* (it can't —
   > the delete was Forbidden). The fix was to make the *bounded* operate scope explicit, not to
   > delete a correct line. Precision, not deletion.

2. **Verify the correct fact against primary source.** Never fix off memory or a guess — that's
   exactly how over-claims get shipped. Ground it: run `--help`, read the real
   module/manifest/HCL, query the cluster read-only, check CI / the hook / the runbook. Verify
   second-hand claims *about* a doc against the doc itself, not your recollection of it.

3. **Fix the `SKILL.md` — prefer precision over deletion.** Narrow an over-broad claim, add the
   exact constraint, add a "NOT for / denied" note, and cite the authoritative file so the next
   reader can re-verify. Keep the house format (every fenced code block gets a language tag, or
   `markdownlint` fails CI).

4. **Fix the upstream source too, if the skill just mirrored a wrong doc.** If CLAUDE.md or a
   runbook is also wrong, correct it in the same change so the error doesn't re-seed (durable fix
   over hotfix).

5. **Land it as a focused PR.** One skill, one small PR — easy to review and revert. `markdownlint`
   the `SKILL.md` locally before pushing (catches MD040 untagged fences, etc.). The diff is the
   reviewable record; don't silently auto-edit a shared, committed skill.

## Guardrails

- **If you can't verify the right answer against source, don't guess** — leave a precise note in
  the skill (or open an issue) flagging the uncertainty instead of asserting a fix.
- **Don't widen scope.** Fix the specific inaccuracy; a full rewrite is `skill-creator`'s job.
- **Distinguish content bugs from triggering.** A skill firing when it shouldn't (or not firing) is
  a *description* issue — note it, but it's separate from a wrong fact in the body. (Triggering
  accuracy is currently unmeasured here — the optimizer harness is incompatible with this Claude
  Code version.)
- Adding a brand-new house skill needs a one-line `.gitignore` negation (`!.claude/skills/<name>/`)
  so it's tracked — editing an existing one does not.

## References

- `skill-creator` (global) — authoring a skill from scratch or optimizing its description/triggering
- Operationalizes the house principles: durable-fix-over-hotfix, and verify-everything-against-primary-source.
