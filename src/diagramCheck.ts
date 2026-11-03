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

// Words that give a condition's other outcome in the same sentence: "if X, A, otherwise B", "the rest go to B".
const OTHER_OUTCOME =
  /\b(otherwise|if not|the rest|the others|anything else|in which case|the remaining)\b|(?<!\blike )\beveryone else\b|(?<!\b(?:nobody|no one|nothing|someone|everyone|anything) )\belse\b/i;

// A sentence that says what happens otherwise must give a decision both outcomes; the model tends to
// draw only the first case and drop the rest. Checks one step: the diagram before and after `sentence`.
export function findStepProblems(before: DiagramState, sentence: string, after: DiagramState): string[] {
  if (!OTHER_OUTCOME.test(sentence)) return [];
  const existing = new Set(before.edges.map((edge) => JSON.stringify(edge)));
  const answered = new Set(after.edges.filter((edge) => isDecision(edge[0]) && !existing.has(JSON.stringify(edge))).map(([from]) => from));
  if (answered.size === 0) return ["the sentence says what happens otherwise, but no decision gets an outcome"];
  return [...answered]
    .filter((decision) => after.edges.filter(([from]) => from === decision).length === 1)
    .map((decision) => `"${decision}" has one outcome, but the sentence says what happens otherwise`);
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
