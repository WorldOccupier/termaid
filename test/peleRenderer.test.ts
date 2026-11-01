import { test } from "node:test";
import assert from "node:assert/strict";
import { InvalidMermaidError, PeleRenderer } from "../src/peleRenderer.ts";

test("rejects invalid Mermaid with a readable error", () => {
  assert.throws(() => new PeleRenderer().validate("flowchart LR\n  a -->"), InvalidMermaidError);
});
