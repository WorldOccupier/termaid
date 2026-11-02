import type { FlowDirection } from "./diagram.ts";

// The model was never trained on layout changes and turns "make it top to bottom" into edges, so short
// sentences that only ask for a direction are handled in code.
const MAX_WORDS = 8;
const TOP_DOWN = /\b(top[\s-]+(to|down)[\s-]+bottom|vertical(ly)?|downwards?)\b/i;
const LEFT_RIGHT = /\b(left[\s-]+to[\s-]+right|horizontal(ly)?|sideways)\b/i;

export function requestedDirection(sentence: string): FlowDirection | undefined {
  if (sentence.trim().split(/\s+/).length > MAX_WORDS) return undefined;
  if (TOP_DOWN.test(sentence)) return "TD";
  if (LEFT_RIGHT.test(sentence)) return "LR";
  return undefined;
}
