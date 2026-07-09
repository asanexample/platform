# refplat public docs site

The public documentation site at **[refplat.org](https://refplat.org)** — an
[Astro](https://astro.build) + [Starlight](https://starlight.astro.build) render of this repo's
canonical docs. Hosted on Railway.

## Single source → this renderer

The content is **not** authored here. It is single-sourced from the platform repo and copied in at
build time by `sync.mjs`:

- `docs/learn/**` → in-site routes (`/<module>/<page>/`)
- `docs/adrs/**` → `/adrs/<stem>`
- cross-tree links (architecture, runbooks, examples) → `main`-pinned GitHub URLs

So `src/content/docs/`, `src/sidebar.json`, and the copied posters in `public/` are **generated**
(git-ignored) — never edit them by hand. Fix the canonical file under `docs/learn/` and re-sync.

The same canonical SVGs also render in Backstage TechDocs; `scripts/theme-svg.mjs` bakes the dark
theme on the way in. See `DIAGRAMS.md` for the diagram pipeline and the Claude Design contract.

## Build

```bash
npm ci
node sync.mjs        # generate src/content/docs + sidebar.json from ../docs/learn (+ ../docs/adrs)
npm run build        # -> dist/
npm start            # serve dist/ on $PORT (production static server)
```

`sync.mjs` derives the repo root from its own location (`../`), so no env var is needed when
vendored here; set `PLATFORM_REPO=<path>` to point at an out-of-tree checkout.

## Local dev

```bash
npm ci
node sync.mjs
npm run dev          # http://localhost:4321
```

Re-run `node sync.mjs` whenever the canonical docs change.

## Deploy

Automatic: **`.github/workflows/deploy-site.yml`** deploys to Railway on every push to `main` that
touches `docs/learn/**`, `docs/adrs/**`, or `site/**`. It syncs the content and runs `railway up`
(Railway rebuilds via Nixpacks and serves `dist/`). Requires the `RAILWAY_TOKEN` repo secret.
