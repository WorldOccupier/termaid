// Ported from the mermaid-diagrams Claude Code plugin (MIT, Srivatsa), renderer/obsidian.mjs.
// Obsidian: a black canvas with a soft spotlight, and a muted colour per
// node. The look of every picture the mod draws.

const SANS = "'Avenir Next', 'Helvetica Neue', Helvetica, Arial, sans-serif"
const MONO = "'SF Mono', Menlo, monospace"

// Blends a colour toward a neutral grey: the same hue, less contrast.
const mute = (hex: string, amount = 0.35, grey = [0x9c, 0x9c, 0xa6]): string => {
  const rgb = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16))
  return '#' + rgb.map((c, i) => Math.round(c * (1 - amount) + grey[i] * amount).toString(16).padStart(2, '0')).join('')
}

// Prism's jewel pairs, one per node in turn, muted.
const HUES = [['#6366f1', '#a855f7'], ['#ec4899', '#f97316'], ['#14b8a6', '#22c55e'], ['#0ea5e9', '#6366f1'], ['#f59e0b', '#ef4444']]
  .map(pair => pair.map(c => mute(c)))
const DECIDE = ['#60a5fa', '#2563eb'].map(c => mute(c))

const linear = (id: string, [a, b]: string[]): string =>
  `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1">` +
  `<stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient>`

const card = (box: Box): string => `x="${box.x}" y="${box.y}" width="${box.w}" height="${box.h}" rx="20"`

import type { Box, NodeInfo, Theme } from "./svgStyler.ts";

export const OBSIDIAN: Theme = {
  // Everything Pele draws outside nodes, edges and labels (class members,
  // pie slices, gantt bars) takes these; dark values throughout, so no
  // diagram type falls back to Pele's light defaults.
  vars: {
    '--pele-bg': '#000000', '--pele-fg': '#ececef', '--pele-muted': '#a1a1aa', '--pele-line': '#5b5b66',
    '--pele-surface': '#0c0c10', '--pele-surface-alt': '#141418', '--pele-border': '#3f3f46',
    '--pele-accent': HUES[0][0], '--pele-error': HUES[1][0], '--pele-critical': HUES[4][0],
    '--pele-font': SANS, '--pele-font-mono': MONO,
    ...Object.fromEntries([...HUES.map(pair => pair[0]), HUES[0][1], HUES[1][1], HUES[2][1]]
      .map((c, i) => [`--pele-series-${i + 1}`, c])),
  },
  radius: 10,
  defs: () =>
    `<radialGradient id="spot"><stop offset="0" stop-color="#ffffff" stop-opacity="0.075"/>` +
    `<stop offset="1" stop-color="#ffffff" stop-opacity="0"/></radialGradient>` +
    `<pattern id="odots" width="20" height="20" patternUnits="userSpaceOnUse">` +
    `<circle cx="10" cy="10" r="0.8" fill="#ffffff"/></pattern>` +
    HUES.map((pair, i) => linear(`o${i}`, pair)).join('') + linear('odecide', DECIDE),
  // Black, a faint spotlight from the top, a dot grid and a hairline frame.
  backdrop: (box: Box) =>
    `<rect ${card(box)} fill="#000000"/>` +
    `<ellipse cx="${box.x + box.w / 2}" cy="${box.y}" rx="${box.w * 0.6}" ry="${box.h * 0.65}" fill="url(#spot)"/>` +
    `<rect ${card(box)} fill="url(#odots)" opacity="0.06"/>` +
    `<rect x="${box.x + 0.5}" y="${box.y + 0.5}" width="${box.w - 1}" height="${box.h - 1}" rx="20" fill="none" stroke="#1c1c20"/>`,
  node: (n: NodeInfo) => ({
    fill: '#0c0c10', stroke: n.isDecision ? 'url(#odecide)' : `url(#o${n.index % HUES.length})`, width: 1.2,
    text: `fill="${n.isDecision ? '#cbd8ec' : '#ececef'}" font-weight="500"`,
  }),
  edges: { stroke: '#5b5b66', width: 1.6, marker: '#8b8b96' },
  // Edge labels are small boxes like the nodes, in the nodes' face at the
  // size Pele measured them, so each box fits its words.
  labels: { fill: '#0c0c10', stroke: '#2a2a30', text: '#b4b4bd', weight: 500, rx: 6 },
  clusters: { fill: '#ffffff', fillOpacity: 0.025, stroke: '#3f3f46', dash: '5 5', text: '#8b8b96' },
  lifelines: { stroke: '#3f3f46', dash: '1 6', cap: 'round', width: 2 },
}
