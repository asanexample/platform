---
name: learning-portal-diagrams
description: >-
  How to place, replace, fix, and process the SVG diagrams in the learning portal (`docs/learn/**`),
  which render in BOTH Backstage TechDocs and the public Astro/Starlight site (`../refplat-site`). Use
  WHENEVER you: drop a new diagram into a learn doc or replace a `mermaid` block with one; fix a
  diagram a reviewer says is broken (text overflowing a box left/right or bottom, boxes too tight,
  "dead space", glued words, a broken/blank image); process a fresh SVG handed off from Claude Design;
  add a wide/poster diagram that overflows the content column; or write/adjust the Claude Design
  generation prompt. Covers the single-source→two-renderers model, the `theme-svg.mjs` processor
  (dark-theme bake + `xml:space` fix + malformed-SVG lint), the MANDATORY real-Chrome preview (rsvg
  font metrics lie — it is why overflow/clipping slips through), the box/text fix recipes (grow-box +
  shift + viewBox; reduce-font-not-wrap; the space-collapse fix), the `astro preview` restart gotcha,
  wide-poster handling (`public/` + click-through), and the Claude Design contract. NOT for authoring
  doc PROSE (that's `maintaining-docs`) or Backstage config (`backstage-portal`).
---

# Learning-portal diagrams

The learn portal's diagrams are **one canonical SVG per figure**, living beside the doc that uses it,
consumed by **two renderers**:

- **Astro/Starlight** — the public site (`../refplat-site`, a sibling repo). This is where you preview.
- **Backstage TechDocs** — mkdocs build → S3. Its HTML sanitizer strips `<iframe>`/embedded HTML/scripts,
  so **an `<img>`-embedded SVG is the only diagram format that works in both**. No inline `<svg>`, no
  `<figure>` HTML, no mermaid-that-needs-a-plugin in a shared doc.

Canonical location: `docs/learn/<module>/images/<name>.svg`, referenced with a **relative** markdown
image `![alt](images/<name>.svg)`. Cross-cutting posters live in the top-level `docs/learn/images/`.

**The generator emits light-mode; the pipeline bakes dark.** Claude Design must NOT ship a dark
`@media (prefers-color-scheme)` block — `theme-svg.mjs` injects it on placement. See "Claude Design
contract" below and `../refplat-site/DIAGRAMS.md`.

## The per-diagram loop (do every one of these, in order)

```text
1. PROCESS   node ../refplat-site/scripts/theme-svg.mjs docs/learn/<mod>/images/<name>.svg
2. PREVIEW   render it in REAL headless Chrome (dark) — NOT rsvg for the final check
3. PLACE     edit the .md (replace the mermaid / insert after the anchor paragraph)
4. BUILD     PLATFORM_REPO=<repo> node sync.mjs && npm run build   (in ../refplat-site)
5. RESTART   pkill -f "astro preview"; npm run preview &            (it serves a STATIC build)
6. VERIFY    re-screenshot the built page in Chrome before handing back
```

Mirror every SVG edit to **both** the working checkout AND the main checkout if you're on a worktree —
the build reads whichever `PLATFORM_REPO` points at, but keep them in sync.

## Step 1 — process the SVG

`../refplat-site/scripts/theme-svg.mjs <path>` is idempotent and does four independent passes:

- **Space-collapse fix** — adds `xml:space="preserve"` to the root `<svg>` when it has `<tspan>`s and is
  minified. Without it, the space between a styled tspan and the next word collapses and glues them
  (`_base.hclwalks`, `theXEnvironmentReady`). Runs on any SVG, themed or not.
- **Malformed lint** — warns on a **duplicate attribute** (e.g. `class` twice → invalid XML → silent
  broken image) and raw C1/`nbsp` bytes (use `&#160;`, not a literal byte).
- **Accent-bar corner fix** — Claude Design draws a thin colored accent bar along a container edge as a
  **straight** rect, so its square ends poke past the container's ROUNDED corners and the corners get no
  accent. This pass replaces the bar with the container's rounded-rect **outline as a colored stroke**
  (`fill="none"`, `stroke-width` 2.5, inset by half so it sits just inside the edge) **clipped to that one
  edge's corner region** (a strip `rx`-deep, pulled in ~2px so it stops as the corner finishes and doesn't
  bleed onto the flat edge) — so the accent *hugs* the rounded corner. Works for any edge (left/right/top/
  bottom). Idempotent and **re-tunable**: on a re-run it recovers the container geometry from an existing
  stroke accent's own `stroke-width` and re-emits, so changing the thickness/inset constants and re-running
  updates every already-processed diagram. Don't hand-edit these accents — change the constants in the
  processor and re-run. **Verify at HIGH zoom in Chrome that the CURVE itself is colored** — at normal zoom a
  straight-edge-only accent looks identical to a corner-following one (this trap cost several rounds).
- **Dark theme** — bakes `@media (prefers-color-scheme:dark)`: a generic HSL remap of inline hex fills
  **plus** a class-based remap of the design-system hooks (`f_bg`/`f_*Bg`/`f_*Hl`/`s_*Bd`/`f_text`/
  accents) with proper surface layering. Skipped if already themed. (The stroke accent's colour rides the
  generic `[stroke="#…"]` remap, so accents dark-theme too.)

Then **always** validate it parses: `python3 -c "import xml.dom.minidom as m;m.parse('<path>')"`.

## Step 2 — preview in REAL Chrome (the #1 rule)

**`rsvg-convert` renders text NARROWER and SHORTER than Chrome.** A box that looks fine in an rsvg PNG
overflows in the browser. Every "still broken" round-trip in this project came from trusting rsvg.
`rsvg` is fine for a *fast geometry sanity check* (vertical box overflow); it is **not** the final
word on anything horizontal (text width) or marginal.

**The real check** — screenshot the built page in the `chrome-devtools` MCP, dark-emulated:

```text
new_page http://localhost:4321/<route>/         (or navigate the existing page)
emulate colorScheme=dark
navigate reload (ignoreCache)
evaluate_script: find the img by src substring, scrollIntoView, return its rect
take_screenshot  → Read it
```

To read a dense/wide box clearly, `img.style.width='1400px'` in the eval, or scroll so the box's bottom
is ~30px above the viewport bottom. If `new_page` errors "browser already running", a stale MCP Chrome
holds its profile lock — `pkill -f 'chrome-devtools-mcp/chrome-profile'` (this is the MCP's own Chrome,
never the user's) and retry.

## Step 3 — place it

- **Replacing a mermaid**: match the whole ```` ```mermaid … ``` ```` fence and swap in `![alt](images/<name>.svg)`.
- **Augmenting**: insert on its own line (blank line above and below) at the anchor the reviewer gives —
  usually "after the paragraph ending '…' and before '…'". Don't remove prose/console blocks unless told.
- **Alt text** stands alone for screen-readers/no-image fallback — describe what the diagram shows, not
  "a diagram of X". Use generic example names (`acme`/`globex`), never real team names or account IDs.
- **New spine page / sidebar order**: spine order lives in `SPINE_ORDER` in `sync.mjs`; module order via
  `learnLabel`/`MODULE_LABELS`/`THEMES`. A new module dir must be added to a `THEMES` group or it's orphaned.

## Step 4 — build & restart preview (gotcha)

`npm run preview` is **`astro preview` — a static file server for `dist/`.** It does NOT auto-rebuild and
it will keep serving the old asset hashes from when it started. After any change you MUST:

```bash
cd ../refplat-site
PLATFORM_REPO=<your-checkout> node sync.mjs && npm run build
pkill -f "astro preview"; sleep 1; npm run preview &
```

Then tell the reviewer to **hard-refresh (`Cmd+Shift+R`)** — a soft refresh can serve cached page HTML
pointing at the old asset. If they say "still broken" after a fix you verified, it's almost always this.

## Fix recipes (all box geometry is edited directly in the SVG, then re-verified in Chrome)

| Symptom | Fix |
|---|---|
| **Text bleeds below a box** (last line / bottom pill row on the box edge) | Grow that box's `height`; if it now collides with what's below, shift everything below down by the same delta and grow the `viewBox` height (and the `<svg height=>`). Aim for **≥16px** padding — rsvg's 8px "looks fine" isn't fine in Chrome. |
| **Text overflows a box to the right** | The line is too wide (SVG doesn't wrap). **Reduce that line's `font-size`** (e.g. 13.5→12) so it fits with right margin. Do NOT split a full-width line in half — that leaves the box half-empty ("dead space"). Only hand-wrap if the box is narrow *and* the text is genuinely 2 lines' worth (split at a word boundary, keep tspans intact, grow the box for the extra lines). |
| **Words glued** (`_base.hclwalks`) | `theme-svg.mjs` adds `xml:space="preserve"`; if it was skipped (multi-line SVG), add it to the root `<svg>` by hand. |
| **Broken/blank image** | Duplicate attribute (merge `class="a" … class="b"` → `class="a b"`) or a raw byte (→ `&#160;`). The processor's lint flags both. |
| **Uneven row heights** after growing one box | If a comparison grid, grow the sibling(s) to match, or the reviewer will notice the asymmetry. |
| **Accent border pokes past / doesn't follow a rounded corner, or is too thick / bleeds onto the flat edge** | Don't hand-edit the accent — it's generated by the processor's accent-bar pass (stroke outline clipped to the corner region). Tune the `T` (thickness) / `FI` (corner-clip inset) constants in `theme-svg.mjs` and **re-run the processor** on the affected SVGs; the pass re-tunes existing accents in place. Then Chrome-verify at high zoom that the *curve* is coloured. |

## Wide posters (wider than the ~45rem content column)

- Fit it to the column via `refplat-site/src/styles/learn.css`, keyed by filename
  (`img[src*="<name>"]{width:100%…}`) — keeps the markdown a plain image (single-source).
- Give a click-through to the full-res SVG: a plain image (Astro hashes it for display) **plus** a text
  link `[Open full-res ↗](../images/<name>.svg)`. `sync.mjs` copies top-level `learn/images/*` into
  `public/` and rewrites *links* (not images) to that stable URL — Astro won't serve a linked content
  asset otherwise. A linked-image `[![]()]()` mis-parses the sync regex; keep image and link separate.

## Claude Design generation contract (fewer come in broken)

The full paste-ready prompt is in `../refplat-site/DIAGRAMS.md`. The rules that matter most: emit ONE
minified **light-mode** SVG (no dark `<style>`); `xml:space="preserve"` on root; never repeat an
attribute; entities not raw bytes; **fit the content** — every run inside its box and the viewBox, boxes
sized to content with ≥12px padding all sides, and **body text wrapped to fit its box with right
margin**. Rule "fit" is the one the pipeline can't repair, so it must be right at generation.

## Gotchas

- **rsvg lies on fonts** — real-Chrome verify is not optional (worth repeating; it's the whole reason
  this skill exists).
- **Preview serves a static build** — rebuild AND restart `astro preview`; then hard-refresh.
- **Two renderers, one source** — only `<img>`-SVG works in both; style/behavior tweaks go in the
  Starlight side (CSS / sync transform), never as HTML in the canonical `.md`.
- **Worktree vs main checkout** — keep both copies of an edited SVG in sync.
- **`theme-svg.mjs` is idempotent** — safe to re-run; it skips an already-themed SVG's theming but still
  reports the lint.

## Checklist (before handing a diagram back)

- [ ] Processed with `theme-svg.mjs` (themed + `xml:space` + lint clean) and parses as valid XML.
- [ ] **Screenshotted the built page in real Chrome, dark mode** — box padding, no L/R/bottom overflow,
      no dead space.
- [ ] Placed with standalone alt text, generic names, relative `images/` ref; mermaid fully removed if replacing.
- [ ] `sync.mjs` + `npm run build` clean; `astro preview` restarted; markdownlint clean.
- [ ] Both SVG copies (worktree + main) in sync.
