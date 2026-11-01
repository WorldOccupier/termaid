import type { FlowDirection } from "./diagram.ts";

export type EdgeTuple = [from: string, to: string, label: string];

// The model's view of the diagram: the same JSON shape it replies with.
export interface DiagramState {
  direction: FlowDirection;
  boxes: string[];
  edges: EdgeTuple[];
}

export function emptyState(): DiagramState {
  return { direction: "LR", boxes: [], edges: [] };
}

// The model's JSON is untrusted: keep only well-formed boxes and edges and drop the rest.
export function normalizeReply(reply: unknown): DiagramState {
  const { direction, boxes, edges } = (reply ?? {}) as Record<string, unknown>;
  return {
    direction: direction === "TD" ? "TD" : "LR",
    boxes: Array.isArray(boxes) ? boxes.filter(isNonEmpty).map((box) => box.trim()) : [],
    edges: Array.isArray(edges) ? edges.filter(isEdgeTuple).map(toEdgeTuple) : [],
  };
}

// Keep in sync with format_update_request in training/story.py: compact JSON, same key order.
export function formatUpdateRequest(state: DiagramState, sentence: string): string {
  return `Diagram so far: ${JSON.stringify(state)}\nNext sentence: ${sentence}`;
}

function isEdgeTuple(candidate: unknown): candidate is [string, string, unknown] {
  return Array.isArray(candidate) && isNonEmpty(candidate[0]) && isNonEmpty(candidate[1]);
}

function toEdgeTuple([from, to, label]: [string, string, unknown]): EdgeTuple {
  return [from.trim(), to.trim(), typeof label === "string" ? label.trim() : ""];
}

function isNonEmpty(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}
