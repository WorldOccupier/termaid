import type { FlowDirection } from "./diagram.ts";
import type { DiagramState, EdgeTuple } from "./diagramState.ts";

// Reads back the Mermaid that toMermaid writes, so a saved diagram can be edited by the model.
// Only that exact output format is supported; anything else yields the lines it can recognize.
const HEADER = /^flowchart\s+(TD|LR)\b/;
const NODE = /^(n_\w+)(?:\["(.*)"\]|\{"(.*)"\})$/;
const EDGE = /^(n_\w+)\s+-->(?:\|"(.*)"\|)?\s+(n_\w+)$/;

export function stateFromMermaid(mermaid: string): DiagramState {
  const lines = mermaid.split("\n").map((line) => line.trim()).filter(Boolean);
  const direction = (lines[0]?.match(HEADER)?.[1] ?? "LR") as FlowDirection;
  const labels = new Map<string, string>();
  const edges: EdgeTuple[] = [];
  for (const line of lines.slice(1)) {
    const node = line.match(NODE);
    if (node) labels.set(node[1], unescapeLabel(node[2] ?? node[3]));
    const edge = line.match(EDGE);
    if (edge && labels.has(edge[1]) && labels.has(edge[3])) {
      edges.push([labels.get(edge[1])!, labels.get(edge[3])!, unescapeLabel(edge[2] ?? "")]);
    }
  }
  return { direction, boxes: [...labels.values()], edges };
}

function unescapeLabel(label: string): string {
  return label.replace(/#quot;/g, '"');
}
