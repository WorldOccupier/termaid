import { applyOps, emptyFlowchart, type DiagramOp, type Flowchart } from "./diagram.ts";
import { emptyState, formatUpdateRequest, normalizeReply, type DiagramState, type EdgeTuple } from "./diagramState.ts";
import { toMermaid } from "./mermaid.ts";
import type { JsonCompletionClient } from "./ollamaClient.ts";
import type { MermaidRenderer } from "./peleRenderer.ts";
import { splitSentences } from "./sentences.ts";
import { requestedDirection } from "./layoutCommand.ts";

const CONDITION_CLAUSE = /(^|[\s,(])(only\s+)?(if|when|unless|otherwise|else)\b.*$/i;

// Each edge is a compact [from box, to box, label] tuple: output tokens dominate latency, and
// deriving node ids from box names in code means the model can't produce dangling ids.
// Listing boxes before edges makes the model commit to every entity in the text first; without
// it, branching sentences ("...on a miss, else...") lose boxes and point edges at the wrong one.
const REPLY_SCHEMA = {
  type: "object",
  properties: {
    direction: { type: "string", enum: ["TD", "LR"] },
    boxes: { type: "array", items: { type: "string" } },
    edges: {
      type: "array",
      items: { type: "array", items: { type: "string" }, minItems: 3, maxItems: 3 },
    },
  },
  required: ["direction", "boxes", "edges"],
};

// termaid-lfm3 was fine-tuned on (diagram so far, sentence) steps with this prompt.
const PER_SENTENCE_PROMPT = `You build a flowchart one sentence at a time.
You get the diagram so far as JSON and the next sentence of the description. Reply with the full
updated diagram as JSON: {"direction": "TD" | "LR", "boxes": ["<box>", ...],
"edges": [["<from box>", "<to box>", "<label>"], ...]}.
Keep every existing box and edge unless the sentence changes it. Reuse existing box names exactly
when the sentence mentions the same thing. Add new things, systems or steps as boxes (short
names, 1-3 words), then connect them; every edge must use names listed in boxes.
Labels are short verb phrases (1-4 words) from the text saying how the boxes relate, e.g.
"sends credentials", "reads from". Labels never contain conditions ("if", "when", "otherwise").
Conditions become decision boxes instead: a short question ending in "?", e.g. "Cache miss?".
Connect the box that checks the condition to the decision box with an empty label, then draw
one edge per outcome from the decision box, labeled "yes" or "no", to the box that happens in
that case. A component placed "in front of" a box takes over the edges into that box and gets
an edge "routes to" it. A box that is multiple or replicated keeps its edges and gets the
strategy in its name, e.g. "Database (round robin)". Only include steps the text describes.

Example:
Diagram so far: {"direction":"LR","boxes":[],"edges":[]}
Next sentence: The user logs in to the web app, which asks the API to check the database.
Reply: {"direction": "LR", "boxes": ["User", "Web App", "API", "Database"], "edges": [
  ["User", "Web App", "logs in"], ["Web App", "API", "asks to check"], ["API", "Database", "checks"]]}

Example:
Diagram so far: {"direction":"LR","boxes":["User","Web App","API","Database"],"edges":[["User","Web App","logs in"],["Web App","API","asks to check"],["API","Database","checks"]]}
Next sentence: If the token has expired the API calls the auth server, otherwise it reuses the session.
Reply: {"direction": "LR",
  "boxes": ["User", "Web App", "API", "Database", "Token expired?", "Auth Server", "Session"], "edges": [
  ["User", "Web App", "logs in"], ["Web App", "API", "asks to check"], ["API", "Database", "checks"],
  ["API", "Token expired?", ""], ["Token expired?", "Auth Server", "yes"], ["Token expired?", "Session", "no"]]}

Example:
Diagram so far: {"direction":"LR","boxes":["User","Web App","API"],"edges":[["User","Web App","logs in"],["Web App","API","calls"]]}
Next sentence: There is a gateway in front of the API.
Reply: {"direction": "LR", "boxes": ["User", "Web App", "Gateway", "API"], "edges": [
  ["User", "Web App", "logs in"], ["Web App", "Gateway", "calls"], ["Gateway", "API", "routes to"]]}`;

export class TextToMermaid {
  private readonly llm: JsonCompletionClient;
  private readonly renderer: MermaidRenderer;

  constructor(llm: JsonCompletionClient, renderer: MermaidRenderer) {
    this.llm = llm;
    this.renderer = renderer;
  }

  async convert(description: string): Promise<string> {
    const state = await this.describe(description);
    const mermaid = TextToMermaid.mermaidFor(state);
    this.renderer.validate(mermaid);
    return mermaid;
  }

  // One model call per sentence keeps every step as small as a single-sentence description, so
  // long descriptions don't overwhelm a small model. `onStep` sees the diagram after each sentence.
  // Starting from an existing diagram turns the description into a list of changes to it.
  async describe(
    description: string,
    onStep?: (index: number, state: DiagramState) => void,
    start: DiagramState = emptyState(),
  ): Promise<DiagramState> {
    let state = start;
    const sentences = splitSentences(description);
    for (const [index, sentence] of sentences.entries()) {
      const direction = requestedDirection(sentence);
      state = direction ? { ...state, direction } : await this.update(state, sentence);
      onStep?.(index, state);
    }
    return state;
  }

  private async update(state: DiagramState, sentence: string): Promise<DiagramState> {
    const request = formatUpdateRequest(state, sentence);
    return normalizeReply(await this.llm.completeJson(PER_SENTENCE_PROMPT, request, REPLY_SCHEMA));
  }

  /// The Mermaid source for a diagram state (unvalidated).
  static mermaidFor(state: DiagramState): string {
    return toMermaid(buildFlowchart(state));
  }
}

function buildFlowchart(state: DiagramState): Flowchart {
  const flowchart = emptyFlowchart(state.direction);
  return applyOps(flowchart, [...state.boxes.map(toNodeOp), ...state.edges.flatMap(toOps)]);
}

// The prompt asks for conditions as questions, so a trailing "?" marks a decision diamond.
function toNodeOp(boxName: string): DiagramOp {
  return { op: "add_node", id: nodeIdFor(boxName), label: boxName, shape: boxName.endsWith("?") ? "decision" : "box" };
}

function toOps([from, to, rawLabel]: EdgeTuple): DiagramOp[] {
  const label = withoutCondition(rawLabel);
  return [
    toNodeOp(from),
    toNodeOp(to),
    { op: "add_edge", from: nodeIdFor(from), to: nodeIdFor(to), label: label || undefined },
  ];
}

// Box names that differ only in case or spacing are the same box.
function nodeIdFor(boxName: string): string {
  return boxName.trim().toLowerCase().replace(/\s+/g, "_");
}

// Small models keep writing conditions into labels despite the prompt, so cut them in code:
// "returns token if valid" -> "returns token", "if tests pass" -> "".
function withoutCondition(label: string): string {
  return label.replace(CONDITION_CLAUSE, "").trim();
}
