import type { Flowchart, FlowEdge, FlowNode } from "./diagram.ts";

const INDENT = "  ";

export function toMermaid(diagram: Flowchart): string {
  const lines = [
    `flowchart ${diagram.direction}`,
    ...diagram.nodes.map(formatNode),
    ...diagram.edges.map(formatEdge),
  ];
  return lines.join(`\n${INDENT}`) + "\n";
}

// Mermaid IDs must be simple tokens, and some words ("end", "graph", "style"...) are keywords.
// Replacing other characters and always prefixing means a box name can never break the syntax.
function sanitizeId(rawId: string): string {
  return `n_${rawId.replace(/[^A-Za-z0-9_]/g, "_")}`;
}

function escapeLabel(label: string): string {
  return label.replace(/"/g, "#quot;");
}

function formatNode(node: FlowNode): string {
  const label = `"${escapeLabel(node.label)}"`;
  const shaped = node.shape === "decision" ? `{${label}}` : `[${label}]`;
  return `${sanitizeId(node.id)}${shaped}`;
}

function formatEdge(edge: FlowEdge): string {
  const arrow = edge.label ? `-->|"${escapeLabel(edge.label)}"|` : "-->";
  return `${sanitizeId(edge.from)} ${arrow} ${sanitizeId(edge.to)}`;
}
