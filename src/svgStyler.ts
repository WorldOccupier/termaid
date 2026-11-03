// Ported from the mermaid-diagrams Claude Code plugin (MIT, Srivatsa), renderer/style.mjs.
// Applies the theme (renderer/obsidian.mjs) to one of Pele's SVGs: swaps
// Pele's own colour tokens for the theme's gradients and fills, frames the
// drawing on the theme's card, then resolves the CSS variables resvg lacks.

export interface Box { x: number; y: number; w: number; h: number }
export interface NodeInfo { index: number; isDecision: boolean }
export interface Theme {
  vars: Record<string, string>;
  radius: number;
  defs: (box: Box) => string;
  backdrop: (box: Box) => string;
  node: (n: NodeInfo) => { fill: string; stroke: string; width: number; text: string };
  edges: { stroke: string; width: number; marker: string };
  labels: { fill: string; stroke: string; text: string; weight: number; rx: number };
  clusters: { fill: string; fillOpacity: number; stroke: string; dash: string; text: string };
  lifelines: { stroke: string; dash: string; cap: string; width: number };
}

// pad: room between the drawing and the card's edge, in SVG units.
export function styled(svg: string, theme: Theme, { pad = 36 } = {}): string {
  // Each node by the order its id first appears, so a sequence diagram's
  // actor keeps one colour at the top and the bottom.
  const ids = new Map<string, number>()
  svg = svg.replace(/<g class="(pele-node(?:\s[^"]*)?)"([^>]*)>([\s\S]*?)<\/g>/g, (_, cls: string, attrs: string, body: string) => {
    const id = /data-id="([^"]*)"/.exec(attrs)?.[1] ?? String(ids.size)
    if (!ids.has(id)) ids.set(id, ids.size)
    const n = theme.node({ index: ids.get(id)!, isDecision: /pele-shape-(diam|hex)/.test(cls) })
    body = body
      .replace(/fill="var\(--_[sa]\)"/g, `fill="${n.fill}"`)
      .replace(/stroke="var\(--_b\)"/g, `stroke="${n.stroke}" stroke-width="${n.width}"`)
      .replace(/<text class="pele-label"([^>]*)>/g, (_, rest: string) => `<text class="pele-label"${merged(rest, n.text)}>`)
    return `<g class="${cls}"${attrs}>${body}</g>`
  })

  const e = theme.edges
  svg = svg
    .replace(/<g class="pele-edges" fill="none" stroke="var\(--_l\)"/,
      `<g class="pele-edges" fill="none" stroke="${e.stroke}" stroke-width="${e.width}"`)
    .replace(/(<path class="pele-marker"[^>]*?)fill="var\(--_l\)"/g, `$1fill="${e.marker}"`)

  const l = theme.labels
  svg = svg
    .replace(/<g class="pele-edge-labels" font-size="([\d.]+)">/,
      `<g class="pele-edge-labels" font-size="$1" fill="${l.text}" font-weight="${l.weight}">`)
    .replace(/<rect x="([-\d.]+)" y="([-\d.]+)" width="([\d.]+)" height="([\d.]+)" rx="3" fill="var\(--_bg\)"\/>/g,
      (_, x: string, y: string, w: string, h: string) => `<rect x="${+x - 7}" y="${+y - 1}" width="${+w + 14}" height="${+h + 2}" rx="${l.rx}" ` +
        `fill="${l.fill}" stroke="${l.stroke}"/>`)

  const c = theme.clusters
  svg = svg
    .replace(/(<g class="pele-cluster"[^>]*>\s*<rect[^>]*?)fill="var\(--_a\)" fill-opacity="0.5" stroke="var\(--_b\)"/g,
      `$1fill="${c.fill}" fill-opacity="${c.fillOpacity}" stroke="${c.stroke}" stroke-dasharray="${c.dash}"`)
    .replace(/<text class="pele-cluster-label" fill="var\(--_m\)"/g,
      `<text class="pele-cluster-label" fill="${c.text}" font-weight="600"`)

  const ll = theme.lifelines
  svg = svg.replace(/<g class="pele-lifelines" fill="none" stroke="var\(--_b\)">/,
    `<g class="pele-lifelines" fill="none" stroke="${ll.stroke}" stroke-dasharray="${ll.dash}" ` +
    `stroke-width="${ll.width}" stroke-linecap="${ll.cap}">`)

  // Frame the drawing on the theme's card, grouped so a host that draws its own surface
  // (the Mac app's drawing card) can drop it.
  const [x, y, w, h] = (svg.match(/viewBox="([^"]+)"/)?.[1] ?? '0 0 800 600').split(/[\s,]+/).map(Number)
  const box = { x: x - pad, y: y - pad, w: w + pad * 2, h: h + pad * 2 }
  svg = svg
    .replace(/viewBox="[^"]+"/, `viewBox="${box.x} ${box.y} ${box.w} ${box.h}"`)
    .replace(/(<svg\b[^>]*?)\swidth="[^"]*"/, '$1').replace(/(<svg\b[^>]*?)\sheight="[^"]*"/, '$1')
    .replace(/(<svg\b[^>]*>)/, `$1<defs>${theme.defs(box)}</defs><g class="termaid-backdrop">${theme.backdrop(box)}</g>`)

  return resolve(svg, { ...theme.vars, '--pele-radius': `${theme.radius}px` })
}

// A tag's attributes with the theme's added, the theme's winning where both
// set one (a class diagram's bold class names already carry font-weight).
function merged(attrs: string, extra = ''): string {
  for (const [, name] of extra.matchAll(/([\w-]+)="/g)) attrs = attrs.replace(new RegExp(`\\s${name}="[^"]*"`), '')
  return `${attrs} ${extra}`
}

// resvg has no CSS variables: theme values first, then the root's own --_x
// definitions, then var() fallbacks.
function resolve(svg: string, vars: Record<string, string>): string {
  const map: Record<string, string> = { ...vars }
  const root = svg.match(/<svg[^>]*style="([^"]*)"/)?.[1] ?? ''
  for (const [, name, value] of root.matchAll(/(--_[\w-]+):([^;]+)/g)) map[name] ??= value
  const sub = (text: string): string => {
    for (let i = 0; i < 5 && text.includes('var('); i++) {
      text = text.replace(/var\((--[\w-]+)(?:,\s*([^()]+))?\)/g, (_, name: string, fb?: string) => map[name] ?? fb ?? '#888')
    }
    return text
  }
  for (const key of Object.keys(map)) map[key] = sub(map[key])
  // Once resolved, the root's custom properties only get in resvg's way: its
  // CSS parser stops at them and never reaches font-family. Nor does it read
  // the font shorthand Pele sizes text with (font:16px sans-serif), so the
  // size is spelled out, or every label falls back to resvg's 12px.
  return sub(svg)
    .replace(/(<svg[^>]*style=")([^"]*)"/, (_, head: string, style: string) => {
      const size = /(?:^|;)\s*font:\s*([\d.]+px)/.exec(style)?.[1]
      return `${head}${style.replace(/--[\w-]+:[^;]*;?/g, '')}${size ? `;font-size:${size}` : ''}"`
    })
    .replace(/style="rx:([\d.]+)px"/g, 'rx="$1"')
}
