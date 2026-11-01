export type FlowDirection = "TD" | "LR";

type NodeShape = "box" | "decision";

export interface FlowNode {
  id: string;
  label: string;
  shape?: NodeShape;
}

export interface FlowEdge {
  from: string;
  to: string;
  label?: string;
}

export interface Flowchart {
  direction: FlowDirection;
  nodes: FlowNode[];
  edges: FlowEdge[];
}

export type DiagramOp =
  | { op: "add_node"; id: string; label: string; shape?: NodeShape }
  | { op: "add_edge"; from: string; to: string; label?: string };

export function emptyFlowchart(direction: FlowDirection = "TD"): Flowchart {
  return { direction, nodes: [], edges: [] };
}

export function applyOps(diagram: Flowchart, ops: DiagramOp[]): Flowchart {
  return ops.reduce(applyOp, copyOf(diagram));
}

function applyOp(diagram: Flowchart, op: DiagramOp): Flowchart {
  if (op.op === "add_node") {
    if (!hasNode(diagram, op.id)) diagram.nodes.push({ id: op.id, label: op.label, shape: op.shape });
    return diagram;
  }
  // Edges may reference nodes the model never declared; create them so the output stays valid.
  for (const id of [op.from, op.to]) {
    if (!hasNode(diagram, id)) diagram.nodes.push({ id, label: id });
  }
  diagram.edges.push({ from: op.from, to: op.to, label: op.label });
  return diagram;
}

// structuredClone isn't available in JavaScriptCore, where native apps run this engine.
function copyOf(diagram: Flowchart): Flowchart {
  return { direction: diagram.direction, nodes: diagram.nodes.map((node) => ({ ...node })), edges: diagram.edges.map((edge) => ({ ...edge })) };
}

function hasNode(diagram: Flowchart, id: string): boolean {
  return diagram.nodes.some((node) => node.id === id);
}
