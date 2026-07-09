# Diagram pipeline

Canonical SVGs live once in `platform/docs/learn/<module>/images/` and are consumed by **both** renderers
(Backstage TechDocs + this Astro/Starlight site). One source, two renderers.

## Processing a new SVG (per diagram)

1. Drop the SVG into the module's `images/` dir.
2. Run the processor: `node scripts/theme-svg.mjs <path>` — it (a) adds `xml:space="preserve"` if missing
   (space-collapse fix), (b) flags malformed defects (duplicate attributes, raw bytes), (c) bakes the
   dark-mode theme (`prefers-color-scheme`, inline-hex + class-based). Idempotent.
3. Preview before shipping: `rsvg-convert -w 1000 -b '#f6f6f3' <path> -o /tmp/x.png` and eyeball it.
   (Preview only — production always uses the SVG.)

The processor is a safety net. It cannot fix **layout** (overflow, clipping, tight boxes) — that must be
correct at generation. See the contract below.

## SVG generation contract (Claude Design)

Emit a clean **light-mode**, **minified** SVG. The pipeline bakes the dark theme — do **not** include your
own dark `<style>` / `prefers-color-scheme`.

1. **`xml:space="preserve"` on the root `<svg>`.** Without it, the space between a styled `<tspan>`
   (mono/colored/bold) and the next word collapses and glues them (`_base.hclwalks`, `theXEnvironmentReady`).
2. **One line.** No newlines/indentation between elements (structural whitespace would render with `preserve`).
3. **Never repeat an attribute** on one element (two `class=`, two `x=`, …). Invalid XML → silent broken image.
4. **Entities, not raw bytes.** Non-breaking space is `&#160;`; use proper UTF-8 for `—`/`→`. No raw C1 bytes.
5. **Fit the content — the pipeline cannot fix this, so it must be right at generation:**
   - Every text run fits inside its box **and** inside the viewBox. Measure it; never clip a box edge or
     overrun the viewBox. (If a label is a hair too wide, shrink the label, not the reader's patience.)
   - Size **boxes to content**, not content to a fixed box. Cards / callouts / code wells need **≥12px
     padding on every side** around all their content (including the *last* line and the *bottom* pill row).
   - When content grows, grow its box and push everything below it down. Keep the viewBox height in sync.
6. **Colors:** inline hex fills, or the established class vocabulary — `f_bg`, `f_blueBg`/`f_greenBg`/`f_ambBg`,
   `f_codeBg`, `f_hl`/`f_blueHl`/`f_greenHl`, `f_text`/`f_muted`/`f_dim`, `f_blue`/`f_green`/`f_amber`,
   and `s_*Bd` borders. Both are themed automatically; the class vocabulary gives better dark-mode layering.
7. **Generic names only** — `acme`/`globex`, never internal team names.

Rules 1, 3, 4 have pipeline safety nets. **Rule 5 (layout/fit) does not** — get it right in generation.
