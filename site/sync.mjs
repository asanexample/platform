// Single-source -> Starlight renderer. Copies the canonical docs (docs/learn + docs/adrs) from the platform
// repo into src/content/docs, adding Starlight frontmatter (title from the H1) and rewriting cross-tree links:
//   - links into docs/adrs  -> in-site /adrs/<stem>   (ADRs are published here)
//   - links within docs/learn -> in-site /<route>     (relative -> root-absolute Starlight route)
//   - links to architecture/runbooks/examples/.claude/anything-else -> main-pinned GitHub blob URLs
// Internal authoring files (_mold, _inventory, _crosslinks) are NOT published.
import { readFileSync, writeFileSync, mkdirSync, rmSync, readdirSync, statSync, copyFileSync } from 'node:fs';
import { dirname, join, relative, resolve, basename, extname } from 'node:path';

// The canonical docs live one level up (this site is vendored at <repo>/site/). Derive the repo root from the
// script location so CI needs no hardcoded path; PLATFORM_REPO can still override for out-of-tree checkouts.
const REPO = process.env.PLATFORM_REPO || new URL('..', import.meta.url).pathname;
const LEARN = join(REPO, 'docs/learn');
const ADRS = join(REPO, 'docs/adrs');
const OUT = new URL('./src/content/docs/', import.meta.url).pathname;
const GH = 'https://github.com/asanexample/platform/blob/main';
// Image assets (diagrams, screenshots) are co-located in the docs tree and referenced with RELATIVE links.
// They keep that relative path in all three renderers (GitHub, mkdocs/TechDocs, Astro) — see the copy pass below.
const IMG_EXT = /\.(svg|png|jpe?g|gif|webp|avif)$/i;

const walk = (d) => readdirSync(d).flatMap((n) => {
  const p = join(d, n);
  return statSync(p).isDirectory() ? walk(p) : [p];
});

// Map a source .md absolute path -> its published route ('' = excluded), and its output path under OUT.
function routeForLearn(abs) {
  let rel = relative(LEARN, abs);                       // e.g. foundations/orientation.md
  if (basename(rel).match(/^_/)) return null;           // internal meta files: not published
  const isReadme = basename(rel).toLowerCase() === 'readme.md';
  const outRel = isReadme ? join(dirname(rel), 'index.md') : rel;
  const routeBody = isReadme ? dirname(rel) : rel.replace(/\.md$/, '');
  const route = '/' + (routeBody === '.' ? '' : routeBody);   // docs/learn/README.md -> '/'
  return { outRel, route };
}
function routeForAdr(abs) {
  const rel = relative(ADRS, abs);
  const isReadme = basename(rel).toLowerCase() === 'readme.md';
  const outRel = join('adrs', isReadme ? 'index.md' : rel);
  const route = isReadme ? '/adrs' : '/adrs/' + rel.replace(/\.md$/, '');
  return { outRel, route };
}

// Resolve a markdown link target (from a file at srcAbs) to its published URL.
function rewriteTarget(target, srcAbs) {
  if (/^(https?:|mailto:|#|\/)/.test(target)) return target;        // external / anchor / already-absolute
  const [path0, anchor] = target.split('#');
  if (!path0) return target;                                        // pure #anchor handled above; guard
  const abs = resolve(dirname(srcAbs), path0);
  const anc = anchor ? '#' + anchor : '';
  if (abs === LEARN || abs.startsWith(LEARN + '/')) {
    if (IMG_EXT.test(abs)) return target;                              // co-located image: keep the relative path (copied into the site)
    if (extname(abs) && extname(abs) !== '.md') return `${GH}/${relative(REPO, abs)}${anc}`; // other non-md asset -> GitHub
    const r = routeForLearn(abs);
    return r ? r.route + anc : `${GH}/${relative(REPO, abs)}${anc}`;
  }
  if (abs === ADRS || abs.startsWith(ADRS + '/')) return routeForAdr(abs).route + anc;
  // anything else in (or above) the repo -> GitHub
  return `${GH}/${relative(REPO, abs)}${anc}`;
}

function transform(srcAbs, route, order) {
  let md = readFileSync(srcAbs, 'utf8');
  // strip an existing frontmatter block if present (rare), we re-add our own
  md = md.replace(/^---\n[\s\S]*?\n---\n/, '');
  // title = first H1; remove that line from the body (Starlight renders the title as the page H1)
  const h1 = md.match(/^#\s+(.+?)\s*$/m);
  const title = (h1 ? h1[1] : basename(srcAbs, '.md')).replace(/`/g, '').trim();
  if (h1) md = md.replace(h1[0] + '\n', '');
  // rewrite inline links  [text](target)  and images  ![alt](target)
  md = md.replace(/(!?)(\[[^\]]*\])\(([^)\s]+)\)/g, (m, bang, label, tgt) => {
    // a click-through LINK (not an image) to a top-level learn/images asset -> its public copy: Astro serves
    // linked images (unlike ![]() ) only from public/, so those refs point there for a stable full-size URL.
    if (!bang) {
      const abs = resolve(dirname(srcAbs), tgt.split('#')[0]);
      if (IMG_EXT.test(abs) && dirname(abs) === join(LEARN, 'images')) return `${label}(/${basename(abs)})`;
      // Link to an internal authoring file (_-prefixed, excluded from publishing) -> UNLINK: keep the text,
      // drop the link. The canonical README keeps the link for GitHub readers; the public site shouldn't
      // surface the doc-authoring scaffolding (_mold/_inventory/_crosslinks) as dead-end GitHub blob links.
      if ((abs === LEARN || abs.startsWith(LEARN + '/')) && /^_/.test(basename(abs))) return label.slice(1, -1);
    }
    return `${bang}${label}(${rewriteTarget(tgt, srcAbs)})`;
  });
  // sidebar.label = a concise label (page titles are long, e.g. "Learn: Delivery — orientation"); sidebar.order
  // controls the reading order within a group (else Starlight sorts alphabetically).
  const sbLabel = learnLabel(srcAbs);
  const sb = [];
  if (order != null) sb.push(`  order: ${order}`);
  if (sbLabel) sb.push(`  label: ${JSON.stringify(sbLabel)}`);
  let fm = `---\ntitle: ${JSON.stringify(title)}\n`;
  if (sb.length) fm += `sidebar:\n${sb.join('\n')}\n`;
  fm += `---\n\n`;
  return fm + md.replace(/^\n+/, '');
}

// Reading order within a group. Spine has a fixed narrative sequence; modules go
// index -> orientation -> tutorial -> deep-dives -> extending -> cheatsheet -> reference; ADRs by number.
const SPINE_ORDER = { 'why-the-platform-exists': 1, 'life-of-a-deployment': 2, 'life-of-a-request': 3, 'how-the-platform-fits': 4, 'architecture-at-a-glance': 5, 'the-security-model': 6 };
function learnOrder(abs) {
  const rel = relative(LEARN, abs);
  const name = basename(rel, '.md');
  if (basename(rel).toLowerCase() === 'readme.md') return 0;
  if (rel.startsWith('spine/')) return SPINE_ORDER[name] ?? 50;
  if (name === 'orientation') return 1;
  if (name.startsWith('tutorial')) return 2;
  if (name.startsWith('deep-dive')) return 3;
  if (name.startsWith('extending') || name.startsWith('how-to')) return 4;
  if (name === 'cheatsheet') return 5;
  if (name === 'reference') return 9;
  return 6;
}
function adrOrder(abs) {
  if (basename(abs).toLowerCase() === 'readme.md') return -1;
  const n = parseInt(basename(abs), 10);
  return Number.isNaN(n) ? 999 : n;
}

// Concise sidebar labels — page titles are long ("Learn: Delivery — orientation"); the sidebar wants short
// ones ("Orientation"). Returns null to fall back to the title (spine narrative docs, ADRs, glossary).
const sentence = (s) => { s = s.replace(/-/g, ' ').trim(); return s.charAt(0).toUpperCase() + s.slice(1); };
function learnLabel(abs) {
  if (abs === ADRS || abs.startsWith(ADRS + '/')) return null;      // ADRs keep "ADR-NNN: …"
  const rel = relative(LEARN, abs);
  if (rel.startsWith('spine/')) return null;                        // spine titles are already clean
  const name = basename(rel, '.md');
  if (name.toLowerCase() === 'readme') return 'Overview';
  if (name === 'orientation') return 'Orientation';
  if (name === 'reference') return 'Reference';
  if (name === 'cheatsheet') return 'Cheatsheet';
  if (name.startsWith('tutorial-')) return 'Tutorial: ' + sentence(name.replace(/^tutorial-/, ''));
  if (name.startsWith('deep-dive-')) return sentence(name.replace(/^deep-dive-/, ''));
  if (name.startsWith('how-to-')) return 'How-to: ' + sentence(name.replace(/^how-to-/, ''));
  if (name.startsWith('extending')) return 'Extending: ' + sentence(name.replace(/^extending-?/, ''));
  return null;
}

// --- generic light->dark SVG theming ---------------------------------------------------------------------
// Safety net so any un-themed SVG adapts to dark. A <style> inside an <img>-loaded SVG is honored and
// prefers-color-scheme follows the OS theme (which Starlight follows). CSS fill/stroke beats inline attrs,
// so attribute selectors remap each palette color. An SVG that already ships prefers-color-scheme is left
// alone (hand-tuned or Claude-Design-baked overrides win).
const hexToRgb = (h) => { h = h.replace('#', ''); if (h.length === 3) h = h.split('').map((c) => c + c).join(''); return [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16)); };
const rgbToHsl = (r, g, b) => { r /= 255; g /= 255; b /= 255; const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn; let h = 0, s = 0; const l = (mx + mn) / 2; if (d) { s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn); h = mx === r ? (g - b) / d + (g < b ? 6 : 0) : mx === g ? (b - r) / d + 2 : (r - g) / d + 4; h /= 6; } return [h, s, l]; };
const hslToHex = (h, s, l) => { let r, g, b; if (!s) { r = g = b = l; } else { const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q, hk = (t) => { if (t < 0) t += 1; if (t > 1) t -= 1; if (t < 1 / 6) return p + (q - p) * 6 * t; if (t < 1 / 2) return q; if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6; return p; }; r = hk(h + 1 / 3); g = hk(h); b = hk(h - 1 / 3); } const to = (x) => Math.round(x * 255).toString(16).padStart(2, '0'); return `#${to(r)}${to(g)}${to(b)}`; };
const clamp = (x, a, b) => Math.min(b, Math.max(a, x));
function darkVariant(hex) {
  const [h, s, l] = rgbToHsl(...hexToRgb(hex));
  // near-white/near-black surfaces read as neutral even with a faint tint (e.g. #f6f6f3 carries S~0.15);
  // only a genuinely-saturated light color is a color *tint* panel.
  const neutral = s < 0.15 || (l > 0.90 && s < 0.30);
  if (neutral) {
    if (l > 0.70) return hslToHex(h, Math.min(s, 0.06), 0.08 + (1 - l) * 0.5); // light surface -> dark neutral
    if (l < 0.35) return hslToHex(h, Math.min(s, 0.10), 0.88);                 // dark text -> light
    return hslToHex(h, Math.min(s, 0.10), clamp(0.95 - l, 0.55, 0.72));        // mid gray (label) -> light-muted
  }
  if (l > 0.80) return hslToHex(h, Math.min(s, 0.55), 0.18 + (1 - l) * 0.5);   // light tint panel -> dark tint
  return hslToHex(h, Math.min(s * 1.05, 1), clamp(l + 0.18, 0.55, 0.72));      // accent -> brightened
}
function themeSvg(svg) {
  const colors = new Set();
  for (const m of svg.matchAll(/(?:fill|stroke)="(#[0-9a-fA-F]{3,6})"/g)) colors.add(m[1]);
  if (!colors.size) return svg;
  const css = [...colors].map((c) => `[fill="${c}"]{fill:${darkVariant(c)}}[stroke="${c}"]{stroke:${darkVariant(c)}}`).join('');
  return svg.replace(/(<svg\b[^>]*?>)/, `$1<style>@media(prefers-color-scheme:dark){${css}}</style>`);
}

// --- run ---
// clear the scaffold's example content
for (const ex of ['guides', 'reference', 'index.mdx', 'index.md', 'adrs']) {
  try { rmSync(join(OUT, ex), { recursive: true, force: true }); } catch {}
}

let learnN = 0, adrN = 0, skipped = 0;
for (const abs of walk(LEARN)) {
  if (extname(abs) !== '.md') continue;
  const r = routeForLearn(abs);
  if (!r) { skipped++; continue; }
  const out = join(OUT, r.outRel);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, transform(abs, r.route, learnOrder(abs)));
  learnN++;
}
// Co-located image assets (diagrams/screenshots): copy preserving the relative path, so the relative refs
// in the .md resolve in Astro exactly as they do on GitHub and in mkdocs/TechDocs.
let imgN = 0, themedN = 0;
for (const abs of walk(LEARN)) {
  if (!IMG_EXT.test(abs)) continue;
  const out = join(OUT, relative(LEARN, abs));
  mkdirSync(dirname(out), { recursive: true });
  let payload = null;
  if (extname(abs).toLowerCase() === '.svg') {
    let svg = readFileSync(abs, 'utf8');
    if (!svg.includes('prefers-color-scheme')) { svg = themeSvg(svg); themedN++; } // auto dark-mode; skip if already themed
    writeFileSync(out, svg);
    payload = svg;
  } else {
    copyFileSync(abs, out);
  }
  // top-level learn/images/* are shared assets (e.g. the architecture poster). Astro won't serve a LINK
  // target that points at a content asset, so also drop these in public/ for a stable click-through URL.
  if (dirname(abs) === join(LEARN, 'images')) {
    const pub = new URL('./public/' + basename(abs), import.meta.url).pathname;
    mkdirSync(dirname(pub), { recursive: true });
    if (payload != null) writeFileSync(pub, payload); else copyFileSync(abs, pub);
  }
  imgN++;
}
const adrList = [];
for (const abs of walk(ADRS)) {
  if (extname(abs) !== '.md') continue;
  const r = routeForAdr(abs);
  const out = join(OUT, r.outRel);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, transform(abs, r.route, adrOrder(abs)));
  adrN++;
  if (basename(abs).toLowerCase() !== 'readme.md') {
    const h1 = readFileSync(abs, 'utf8').match(/^#\s+(.+?)\s*$/m);
    adrList.push({ stem: basename(abs, '.md'), num: parseInt(basename(abs), 10) || 999, title: (h1 ? h1[1] : basename(abs, '.md')).trim() });
  }
}

// Sidebar: concern-grouped + hierarchical. Each theme holds labeled, COLLAPSED module groups so it reads as
// Theme > Module > pages (not one flat wall). Module labels come from each module's own title. Spine leads as
// the onramp (pages shown directly); the two big standalone modules sit at top level; ADRs collapse under Reference.
const titleCase = (d) => d.replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
const MODULE_LABELS = {
  'domain-model': 'Domain Model', 'teams': 'Teams', 'products': 'Onboarding a Product', 'environment-api': 'Environment API',
  'self-service-resources': 'Self-Service Resources', 'delivery': 'Delivery', 'developer-experience': 'Developer Experience',
  'policy': 'Policy & Admission', 'identity': 'Identity & Access', 'supply-chain': 'Supply Chain',
  'runtime-security': 'Runtime Security', 'secrets-config': 'Secrets & Config', 'compliance': 'Compliance',
  'observability': 'Observability', 'cost': 'Cost & FinOps', 'operations': 'Operations',
  'foundations': 'Foundations', 'agentic': 'The Agentic Platform',
};
const modLabel = (dir) => MODULE_LABELS[dir] || titleCase(dir);
const modGroup = (dir) => ({ label: modLabel(dir), collapsed: true, items: [{ autogenerate: { directory: dir } }] });

const THEMES = [
  { label: 'The Model', dirs: ['domain-model', 'teams', 'products', 'environment-api', 'self-service-resources'] },
  { label: 'Delivery & Developer Experience', dirs: ['delivery', 'developer-experience'] },
  { label: 'Security & Governance', dirs: ['policy', 'identity', 'supply-chain', 'runtime-security', 'secrets-config', 'compliance'] },
  { label: 'Running the Platform', dirs: ['observability', 'cost', 'operations'] },
];
const STANDALONE = ['foundations', 'agentic']; // big single modules -> own top-level group (avoids Theme>Module double-label)

// coverage check: every module dir must appear somewhere (so a new module can't silently vanish)
const covered = new Set([...THEMES.flatMap((t) => t.dirs), ...STANDALONE, 'spine']);
const onDisk = readdirSync(OUT, { withFileTypes: true }).filter((e) => e.isDirectory() && e.name !== 'adrs').map((e) => e.name);
const orphaned = onDisk.filter((d) => !covered.has(d));
if (orphaned.length) console.warn('⚠️  module dirs missing from the sidebar:', orphaned.join(', '));

// Group the 98 ADRs into browsable areas (mirroring the module themes) by keyword-matching the title. First
// match wins, so order most-specific first; anything unmatched lands in "Platform & Meta". New ADRs self-file.
const ADR_AREAS = [
  ['Agents', /agent|xagent|autonomy|triage|bedrock|copilot/i],
  ['Observability & Cost', /observ|telemetry|lgtm|mimir|loki|tempo|grafana|prometheus|\bslo\b|alert|cost|finops|opencost|budget|instrument/i],
  ['Security & Governance', /secur|kyverno|policy|admission|identit|keycloak|\bauth|\biam\b|pod.identity|secret|sops|supply.chain|cosign|slsa|sign|provenance|runtime|falco|mtls|zero.?trust|complian|\bwaf\b|firewall|rbac|encrypt|guardduty|\bkms\b|\bsso\b|\bdex\b|\baccess\b|break.?glass/i],
  ['Delivery & Developer Experience', /deliver|argocd|gitops|rollout|promot|release|canary|backstage|scaffold|deploy|pipeline|portal|ci\/cd|\bci\b|oidc|availab|drain|disruption/i],
  ['Environments & Self-Service', /environment|crossplane|tenant|domain|\bproduct|self.?service|composition|claim|sqs|sns|dynamo|resource|namespace|quota|\bteam\b|naming|ownership/i],
  ['Foundations & Infrastructure', /network|\bvpc\b|cidr|transit|\bdns\b|cilium|cluster|\beks\b|\bnode|karpenter|account|\biac\b|terragrunt|opentofu|region|multi.?cloud|\bstate\b|gateway|ingress|bastion|\bssm\b|session.manager|platctl|resilien|continuity|\bprovider\b|version.constraint|tailscale/i],
];
const areaOf = (t) => (ADR_AREAS.find(([, re]) => re.test(t)) || ['Platform & Meta'])[0];
const adrShort = (t) => t.replace(/^ADR[- ]?\d+\s*[:·-]\s*/i, '');
const byArea = {};
for (const a of adrList) (byArea[areaOf(a.title)] ??= []).push(a);
const adrGroups = [...ADR_AREAS.map(([n]) => n), 'Platform & Meta'].filter((a) => byArea[a]).map((area) => ({
  label: area, collapsed: true,
  items: byArea[area].sort((x, y) => x.num - y.num).map((a) => ({ label: `${String(a.num).padStart(3, '0')} · ${adrShort(a.title)}`, slug: `adrs/${a.stem}` })),
}));

const sidebar = [
  { label: 'Start Here', items: [{ autogenerate: { directory: 'spine' } }] },
  ...THEMES.map((t) => ({ label: t.label, items: t.dirs.map(modGroup) })),
  ...STANDALONE.map(modGroup),
  { label: 'Reference', items: [
    { slug: 'glossary' },
    { label: 'Decision Records', collapsed: true, items: [{ slug: 'adrs' }, ...adrGroups] },
  ] },
];
writeFileSync(new URL('./src/sidebar.json', import.meta.url).pathname, JSON.stringify(sidebar, null, 2));

console.log(`learn: ${learnN} published, ${skipped} internal skipped | adrs: ${adrN} | images: ${imgN} (${themedN} auto-themed) | sidebar groups: ${sidebar.length}`);
