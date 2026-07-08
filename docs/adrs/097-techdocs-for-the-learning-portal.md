# ADR-097: TechDocs for the Learning Portal

**Date:** 2026-07-08

**Status:** Accepted — implementing ([#938](https://github.com/asanexample/platform/issues/938))

## Context

The learning portal (`docs/learn/**` — a 5-doc spine plus 17 subsystem modules, ~93 markdown files) is the
platform's teaching layer: orientation narratives + references + deep dives, distinct from the explanatory
ADRs/runbooks. It is complete and on `main`, but it has **no home inside the platform's own developer portal**
— every Developer Experience module honestly flags this as the portal's own "designed / not wired" gap
(#938). Wiring it (a) closes #938, (b) **demonstrates the IDP's docs capability** on the reference platform
("the platform builds and serves its own docs like any other artifact"), and (c) establishes a
**single-source → many-renderers** pattern that a future public **Astro/Starlight** site + blog will reuse.

The Backstage app image already has the **TechDocs backend** registered (`@backstage/plugin-techdocs-backend`
plus the search module) and the **frontend** plugin + mermaid addon as dependencies — but `techdocs` is on
Backstage's **scaffold defaults** (`builder: local`, `generator.runIn: docker`, `publisher: local`) and the
backend image has **no mkdocs** installed. So local generation cannot render in the pod, and the frontend
plugin isn't added to the app's `features` — the capability is present but inert. There is no mkdocs config,
no build pipeline, and no docs-bearing catalog entity for the platform itself.

## Decision

1. **Build mode: `external` + `publisher: awsS3`.** CI pre-builds the site with mkdocs / the techdocs-cli and
   publishes it to an S3 bucket; Backstage serves the pre-built HTML from S3. No mkdocs in the runtime image,
   no runtime generation. This is the Backstage-recommended production pattern and the stronger demo. *Rejected
   `builder: local`:* the pod has neither mkdocs nor docker-in-docker, it would need an image change anyway,
   and it is dev-grade.
2. **Scope: `docs_dir: docs/learn` + a CI link-transform.** The ~760 intra-portal links resolve as-is; the 433
   links that escape `docs/learn` (to `docs/adrs`, `docs/architecture`, `docs/runbooks`, `docs/examples`, and
   `.claude/skills`) are rewritten to absolute `main`-pinned GitHub URLs by
   `.github/scripts/docs/techdocs-linkfix.sh`, operating on a **build copy** so the canonical markdown keeps
   its repo-relative links (which resolve natively on GitHub). *Rejected `docs_dir: docs/`* (serve the whole
   tree, zero rewriting): a bigger, less-curated site needing meta-file exclusions, off-message for #938's
   "learn corpus."
3. **A dedicated docs entity.** A repo-root `catalog-info.yaml` declares a `platform-learning-portal`
   Component with `backstage.io/techdocs-ref: dir:.`, and a repo-root `mkdocs.yml` (`docs_dir: docs/learn`,
   `techdocs-core`) drives the build. The `techdocs.builder/publisher` config + the docs `catalog.locations`
   entry are injected via the Backstage **module's `--config` override** (env-specific bucket stays in infra);
   the app repo only adds the **frontend** techdocs plugin (+ mermaid addon) to `features`.
4. **Single source → many renderers.** `docs/learn` is the canonical source; TechDocs derives from it, and the
   future Astro/Starlight public site reuses the same `techdocs-linkfix.sh` transform.

## Consequences

**Positive.** The learning portal becomes browsable + searchable inside Backstage; mermaid renders; cross-tree
links resolve (to GitHub). The build follows the platform's own CI/OIDC/S3 patterns — a genuine "docs as a
first-class artifact" demo. The link-transform + mkdocs config are reusable for the public site.

**Negative / costs.** The work spans **two repos** (infra here + the app image) and adds an S3 bucket, a
read/write IAM pair (Backstage Pod-Identity read, CI OIDC write), and a CI generate/publish job. Cross-tree
links leave the site (to GitHub) rather than staying in-portal. The mkdocs `nav` is hand-curated (a small
maintenance cost as modules are added). Author-meta files (`_inventory`, `_mold`, `_crosslinks`,
`_screenshots`) build but are omitted from `nav`.

**Follow-ups (out of scope here).** The public **Astro/Starlight** docs site + a marketing/tutorial blog
(reusing the transform); making TechDocs the **tenant-app default** (the scaffolder emitting
`docs/` + `mkdocs.yml` + a `techdocs-ref` annotation — today it emits none).

## References

- [#938](https://github.com/asanexample/platform/issues/938) — the tracking issue.
- [ADR-046](046-back-stack-for-developer-self-service.md), [ADR-051](051-backstage-developer-portal.md) — the
  BACK stack / Backstage developer portal (both mention TechDocs as designed-but-unwired).
- `docs/learn/developer-experience/` — the module documenting the portal (and this gap).
