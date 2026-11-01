import type { DiagramState, EdgeTuple } from "./diagramState.ts";

const OUTCOME_LABELS = ["yes", "no"];

// Rule breaks a correct diagram for the prompt never has; each names what is wrong.
export function findProblems(state: DiagramState): string[] {
  const boxes = allBoxes(state);
  return [
    ...unconnectedBoxes(state, boxes),
    ...boxes.filter(isDecision).flatMap((decision) => decisionProblems(state.edges, decision)),
    ...extraEntryPoints(state.edges),
  ];
}

function isDecision(box: string): boolean {
  return box.endsWith("?");
}

function allBoxes(state: DiagramState): string[] {
  return [...new Set([...state.boxes, ...state.edges.flatMap(([from, to]) => [from, to])])];
}

function unconnectedBoxes(state: DiagramState, boxes: string[]): string[] {
  const connected = new Set(state.edges.flatMap(([from, to]) => [from, to]));
  return boxes.filter((box) => !connected.has(box)).map((box) => `"${box}" is not connected`);
}

function decisionProblems(edges: EdgeTuple[], decision: string): string[] {
  const outcomes = edges.filter(([from]) => from === decision);
  const labels = outcomes.map(([, , label]) => label);
  const problems: string[] = [];
  if (outcomes.length === 0) problems.push(`"${decision}" has no outcomes`);
  if (labels.some((label) => !OUTCOME_LABELS.includes(label)) || new Set(labels).size !== labels.length) {
    problems.push(`"${decision}" outcomes must be one "yes" and/or one "no"`);
  }
  if (outcomes.length === 2 && outcomes[0][1] === outcomes[1][1]) {
    problems.push(`"${decision}" sends yes and no to the same box`);
  }
  if (edges.filter(([, to]) => to === decision).length !== 1) {
    problems.push(`"${decision}" needs exactly one box checking it`);
  }
  return problems;
}

// A process has one starting point; a second box nothing leads into is usually a step the model
// left beside the flow instead of inside it ("customs inspects parcels before the depot").
function extraEntryPoints(edges: EdgeTuple[]): string[] {
  const reached = new Set(edges.map(([, to]) => to));
  const entries = [...new Set(edges.map(([from]) => from))].filter((box) => !reached.has(box));
  return entries.slice(1).map((box) => `nothing leads into "${box}"`);
}
