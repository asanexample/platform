// Process a canonical doc SVG so it renders correctly in BOTH renderers (Backstage TechDocs + Astro
// Starlight). Idempotent. Three passes, each independent:
//   1. SPACE-COLLAPSE FIX  -> add xml:space="preserve" to the <svg> root when the SVG has <tspan> and is
//      minified. Claude Design emits styled tspans (mono/colored/bold) whose inter-token space is a *leading
//      tspan space*; SVG's default whitespace handling COLLAPSES it, gluing words (`_base.hclwalks`). preserve
//      keeps it. Safe on minified (single-line) SVGs — there's no structural whitespace to preserve.
//   2. MALFORMED CHECK     -> flag the known Claude Design defects: a tag with a duplicate attribute
//      (e.g. class twice) and raw non-ASCII control bytes. These render as a *broken image*, silently.
//   3. DARK THEME          -> bake a prefers-color-scheme:dark theme (generic inline-hex remap + the
//      class-based design-system remap with proper surface layering). Skipped if already themed.
import { readFileSync, writeFileSync } from 'node:fs';

// ---------- 1. space-collapse fix ----------
function spaceFix(svg) {
  if (!svg.includes('<tspan')) return { svg, applied: false };
  if (/\bxml:space=/.test(svg)) return { svg, applied: false, note: 'already has xml:space' };
  if (svg.split('\n').length > 2) return { svg, applied: false, note: 'multi-line — not blanket-safe, inspect manually' };
  return { svg: svg.replace(/<svg /, '<svg xml:space="preserve" '), applied: true };
}

// ---------- 2. malformed check (warn, don't mutate) ----------
function lint(svg) {
  const warns = [];
  const dup = svg.match(/<[a-z]+\b[^>]*\bclass="[^"]*"[^>]*\bclass="[^"]*"[^>]*>/);
  if (dup) warns.push('duplicate `class` attribute (invalid XML -> broken image): ' + dup[0].slice(0, 80));
  // raw C1 control / lone high bytes that aren't valid UTF-8 lead bytes in a &-free run
  if (/[\x80-\x9f]/.test(svg)) warns.push('raw C1 control byte present (use &#160; not a literal nbsp byte)');
  // accent TEXT-colour class (f_blue/f_green/f_amber/f_red) on a LIGHT-TINT SHAPE fill: the dark bake maps the
  // class to a saturated accent that WINS over the inline fill (CSS class beats presentation attr), so a pale chip
  // flattens to that accent — losing its intended tint and hiding any same-accent glyph inside it (e.g. an amber
  // number on an amber chip goes invisible). A pale chip should carry ONLY its inline tint (no accent class); the
  // glyph keeps the saturated inline colour. (A solid accent *badge* — dark/saturated fill, contrasting text — is
  // fine, so we gate on the fill being light.) See the "add an engine" chip fix.
  const lightHex = (h) => { h = h.replace('#', ''); if (h.length === 3) h = h.split('').map((c) => c + c).join(''); const v = [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)); return (Math.max(...v) + Math.min(...v)) / 510; };
  for (const m of svg.matchAll(/<(?:rect|circle|ellipse|path|polygon|polyline)\b[^>]*\bclass="[^"]*\bf_(?:blue|green|amber|red)\b[^"]*"[^>]*>/g)) {
    const fill = (m[0].match(/\bfill="(#[0-9a-fA-F]{3,6})"/) || [])[1];
    if (fill && lightHex(fill) > 0.72) { warns.push('accent colour class on a light-tint SHAPE — flattens in dark, hides same-accent glyphs; drop the class, keep the inline fill: ' + m[0].slice(0, 90)); break; }
  }
  return warns;
}

// ---------- 3. dark theme ----------
const hexToRgb = (h) => { h = h.replace('#', ''); if (h.length === 3) h = h.split('').map((c) => c + c).join(''); return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)); };
const rgbToHsl = (r, g, b) => { r /= 255; g /= 255; b /= 255; const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn; let h = 0, s = 0; const l = (mx + mn) / 2; if (d) { s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn); h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h /= 6; } return [h, s, l]; };
const hslToHex = (h, s, l) => { let r, g, b; if (!s) { r = g = b = l; } else { const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q, hk = (t) => { if (t < 0) t += 1; if (t > 1) t -= 1; if (t < 1 / 6) return p + (q - p) * 6 * t; if (t < 1 / 2) return q; if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6; return p; }; r = hk(h + 1 / 3); g = hk(h); b = hk(h - 1 / 3); } const to = (x) => Math.round(x * 255).toString(16).padStart(2, '0'); return `#${to(r)}${to(g)}${to(b)}`; };
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
function darkVariant(hex) {
  const [h, s, l] = rgbToHsl(...hexToRgb(hex));
  const neutral = s < 0.15 || (l > 0.90 && s < 0.30);
  if (neutral) {
    if (l > 0.70) return hslToHex(h, Math.min(s, 0.06), 0.08 + (1 - l) * 0.5);
    if (l < 0.35) return hslToHex(h, Math.min(s, 0.10), 0.88);
    return hslToHex(h, Math.min(s, 0.10), clamp(0.95 - l, 0.55, 0.72));
  }
  if (l > 0.80) return hslToHex(h, Math.min(s, 0.55), 0.18 + (1 - l) * 0.5);
  return hslToHex(h, Math.min(s * 1.05, 1), clamp(l + 0.18, 0.55, 0.72));
}
function genericStyle(svg) {
  const colors = new Set();
  for (const m of svg.matchAll(/(?:fill|stroke)="(#[0-9a-fA-F]{3,6})"/g)) colors.add(m[1]);
  if (!colors.size) return '';
  const css = [...colors].map((c) => `[fill="${c}"]{fill:${darkVariant(c)}}[stroke="${c}"]{stroke:${darkVariant(c)}}`).join('');
  return `<style>@media(prefers-color-scheme:dark){${css}}</style>`;
}
const CLASS_DARK = {
  f_bg: ['fill', '#15161c'],
  f_blueBg: ['fill', '#172a50'], f_greenBg: ['fill', '#16331f'], f_ambBg: ['fill', '#2b2410'], f_codeBg: ['fill', '#0e0f14'],
  f_hl: ['fill', '#16243f'], f_blueHl: ['fill', '#16243f'], f_greenHl: ['fill', '#102a1c'], f_ambHl: ['fill', '#241d0c'],
  s_blueBd: ['stroke', '#40639e'], s_greenBd: ['stroke', '#2f6a45'], s_ambBd: ['stroke', '#6b5520'], s_codeBd: ['stroke', '#2a2b33'],
  s_blueHlBd: ['stroke', '#5a7fc0'], s_greenHlBd: ['stroke', '#3f8a5c'], s_ambHlBd: ['stroke', '#8a6f2e'],
  s_narrow: ['stroke', '#33343c'], f_narrow: ['stroke', '#33343c'],
  f_text: ['fill', '#e6e6ea'], f_muted: ['fill', '#9a9aa3'], f_dim: ['fill', '#74747d'],
  f_blue: ['fill', '#7fa0ee'], f_green: ['fill', '#4fd08a'], f_amber: ['fill', '#e0b050'],
};
function classStyle(svg) {
  const present = Object.keys(CLASS_DARK).filter((c) => new RegExp(`class="[^"]*\\b${c}\\b`).test(svg));
  if (!present.length) return '';
  const css = present.map((c) => { const [prop, val] = CLASS_DARK[c]; return `.${c}{${prop}:${val}}`; }).join('');
  return `<style>@media(prefers-color-scheme:dark){${css}}</style>`;
}

// ---------- accent-bar corner fix ----------
// Claude Design draws a thin colored accent bar/border along a container edge as a straight rect, so its
// square ends poke past the container's ROUNDED corners (and the corners themselves get no accent). Make the
// accent FOLLOW the corners: draw the container's rounded-rect OUTLINE as a colored STROKE (fill=none) and
// CLIP it to just that edge's corner region — so the thick accent traces the rounded corner instead of
// stopping at the straight run. Handles a fresh thin bar AND converts an earlier clip-FILL accent. Idempotent
// (skips a rect that's already a stroke accent, i.e. carries fill="none").
function insetAccentBars(svg) {
  const num = (t, k) => { const m = t.match(new RegExp(`\\b${k}="([0-9.]+)"`)); return m ? parseFloat(m[1]) : null; };
  const str = (t, k) => { const m = t.match(new RegExp(`\\b${k}="([^"]*)"`)); return m ? m[1] : ''; };
  const f = (n) => (+n).toFixed(1);
  const T = 2.5;  // accent stroke thickness (px)
  const FI = 2;   // pull the corner clip in this far so the accent stops as the corner finishes (no bleed onto the flat edge)
  const body = svg.replace(/<defs>[\s\S]*?<\/defs>/g, ' '); // don't treat clip rects inside <defs> as bars
  const rects = [...body.matchAll(/<rect\b[^>]*>/g)].map((m) => {
    const t = m[0];
    return { raw: t, x: num(t, 'x'), y: num(t, 'y'), w: num(t, 'width'), h: num(t, 'height'), rx: num(t, 'rx'),
      clip: (t.match(/clip-path="url\(#([^)]+)\)"/) || [])[1], none: /fill="none"/.test(t) };
  });
  const containers = rects.filter((r) => r.w > 100 && r.rx > 2 && r.h > 30);
  // clip covering one edge's straight run + its two rounded corners, stopping FI px short of the corner-to-flat tangent
  const clipFor = (c, edge) => edge === 'left'
    ? `<rect x="${f(c.x - 1)}" y="${f(c.y - 1)}" width="${f(c.rx - FI + 1)}" height="${f(c.h + 2)}"/>`
    : edge === 'right'
    ? `<rect x="${f(c.x + c.w - c.rx + FI)}" y="${f(c.y - 1)}" width="${f(c.rx - FI + 1)}" height="${f(c.h + 2)}"/>`
    : edge === 'top'
    ? `<rect x="${f(c.x - 1)}" y="${f(c.y - 1)}" width="${f(c.w + 2)}" height="${f(c.rx - FI + 1)}"/>`
    : `<rect x="${f(c.x - 1)}" y="${f(c.y + c.h - c.rx + FI)}" width="${f(c.w + 2)}" height="${f(c.rx - FI + 1)}"/>`;
  const edgeOf = (c, sx, sy, sw, sh) => sw < sh
    ? (Math.abs(sx - c.x) <= 3 ? 'left' : 'right')
    : (Math.abs(sy - c.y) <= 3 ? 'top' : 'bottom');
  let out = svg, defs = [], n = 0;
  for (const bar of rects) {
    let c, edge, cid = null;
    if (bar.none && bar.clip) {                                                // an existing stroke accent -> RE-TUNE
      const To = num(bar.raw, 'stroke-width') || T;                            // recover container by undoing the old inset
      if (To === T) continue;                                                  // already at current thickness — leave it (idempotent; recover→re-emit rounds by 0.1px, so re-emitting would drift)
      c = { x: bar.x - To / 2, y: bar.y - To / 2, w: bar.w + To, h: bar.h + To, rx: bar.rx + To / 2 };
      cid = bar.clip;
      const cp = svg.match(new RegExp(`<clipPath id="${cid}"><rect([^>]*)>`));
      if (!cp) continue;
      edge = edgeOf(c, num(cp[1], 'x'), num(cp[1], 'y'), num(cp[1], 'width'), num(cp[1], 'height'));
    } else if (bar.none) {
      continue;                                                                // a non-accent fill="none" rect — leave it
    } else if (bar.clip) {                                                     // a legacy clip-FILL accent -> convert
      c = bar; cid = bar.clip;                                                 // its geometry already IS the container's
      const cp = svg.match(new RegExp(`<clipPath id="${cid}"><rect([^>]*)>`));
      if (!cp) continue;
      edge = edgeOf(c, num(cp[1], 'x'), num(cp[1], 'y'), num(cp[1], 'width'), num(cp[1], 'height'));
    } else {                                                                   // a fresh thin bar
      if ([bar.x, bar.y, bar.w, bar.h].some((v) => v == null)) continue;
      if (Math.min(bar.w, bar.h) > 6 || Math.max(bar.w, bar.h) < 30) continue; // not a thin accent bar/border
      const vertical = bar.h > bar.w;
      c = containers.find((c) => vertical
        ? (Math.abs(c.x - bar.x) <= 3 || Math.abs(c.x + c.w - bar.x - bar.w) <= 3) && bar.y >= c.y - 6 && bar.y + bar.h / 2 <= c.y + c.h
        : (Math.abs(c.y - bar.y) <= 3 || Math.abs(c.y + c.h - bar.y - bar.h) <= 3) && bar.x >= c.x - 6 && bar.x + bar.w / 2 <= c.x + c.w);
      if (!c) continue;
      edge = vertical ? (Math.abs(c.x - bar.x) <= 3 ? 'left' : 'right') : (Math.abs(c.y - bar.y) <= 3 ? 'top' : 'bottom');
    }
    const color = str(bar.raw, 'stroke') || str(bar.raw, 'fill') || '#000', sc = /\/>\s*$/.test(bar.raw);
    if (!cid) cid = `abar${n}`;
    // container outline as a T-px stroke, inset by T/2 so it sits just inside the edge; clipped to this edge
    const accent = `<rect x="${f(c.x + T / 2)}" y="${f(c.y + T / 2)}" width="${f(c.w - T)}" height="${f(c.h - T)}" rx="${f(Math.max(c.rx - T / 2, 0.5))}" fill="none" stroke="${color}" stroke-width="${T}" clip-path="url(#${cid})"${sc ? '/>' : '>'}`;
    out = out.replace(bar.raw, accent);
    if (bar.clip) out = out.replace(new RegExp(`(<clipPath id="${cid}">)<rect[^>]*>`), `$1${clipFor(c, edge)}`);
    else defs.push(`<clipPath id="${cid}">${clipFor(c, edge)}</clipPath>`);
    n++;
  }
  if (defs.length) out = out.replace(/(<svg\b[^>]*?>)/, `$1<defs>${defs.join('')}</defs>`);
  return { svg: out, n };
}

// ---------- run ----------
const p = process.argv[2];
let s = readFileSync(p, 'utf8');
let did = [];
for (const w of lint(s)) console.log('  ⚠ LINT:', w);
const sf = spaceFix(s); s = sf.svg;
if (sf.applied) did.push('space-fix');
else if (sf.note) console.log('  · space-fix skipped:', sf.note);
const ab = insetAccentBars(s); s = ab.svg;
if (ab.n) did.push(`accent-bars(${ab.n})`);
if (!s.includes('prefers-color-scheme')) {
  const inject = genericStyle(s) + classStyle(s);
  if (inject) { s = s.replace(/(<svg\b[^>]*?>)/, `$1${inject}`); did.push(classStyle(s) ? 'theme(inline+class)' : 'theme(inline)'); }
}
if (did.length) { writeFileSync(p, s); console.log('processed [' + did.join(', ') + ']:', p); }
else console.log('no change:', p);
