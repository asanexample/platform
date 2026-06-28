<!-- markdownlint-disable-file MD041 -->
<!--
Thanks for the PR. Fill in the summary, then run the docs-impact check below — keeping docs current
as we move fast is the point (see the `maintaining-docs` skill for the full doc-impact map).
-->

## Summary

<!-- What changed and why. Link the issue/ADR. -->

## Docs impact

Tick what applies and confirm the doc is updated **in this PR** (or say "n/a — code-only, no
doc surface affected"):

- [ ] **Added / renamed / removed a module** → its `README.md` regenerated (`terraform-docs --config
      .terraform-docs.yml <module>`), and added to `CLAUDE.md` + `infra/docs/17-available-modules.md`.
      *(CI blocks a module with no README and stale terraform-docs on changed modules.)*
- [ ] **Renamed or retired a term / mechanism / file** (auth model, CRD kind, registry, unit) →
      grepped every doc surface (`docs/ .claude/skills/ CLAUDE.md README.md ROADMAP.md infra/docs/`
      + module READMEs) and reconciled each hit, **including debug/verify steps**.
- [ ] **Flipped a status** (Kyverno Audit→Enforce, ADR Proposed→Accepted, planned→shipped) → ADR
      Status + `docs/adrs/README.md`, `CLAUDE.md`, `ROADMAP.md`, and the relevant house skill.
- [ ] **Shipped a user-facing capability** → `ROADMAP.md`; a `docs/runbooks/` entry if it's operated;
      a `.claude/skills/` skill if others author against it; the `docs/README.md` index.
- [ ] **Made a "future / not-yet-built / planned" claim become true** → fixed that doc.
- [ ] **Touched a domain a house skill covers** → skill updated.
- [ ] n/a — code-only, no documentation surface is affected.

> Couldn't fully fix a doc here? Don't leave it silently wrong — add a dated `> NOTE:` in the doc and
> open a tracking issue (see the `maintaining-docs` skill, "flag, don't drift").
