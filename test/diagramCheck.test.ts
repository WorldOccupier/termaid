import { test } from "node:test";
import assert from "node:assert/strict";
import { findProblems, findStepProblems } from "../src/diagramCheck.ts";

test("passes a well-formed decision diagram", () => {
  const edges: [string, string, string][] = [["API", "Cache miss?", ""], ["Cache miss?", "DB", "yes"], ["Cache miss?", "Cache", "no"]];
  assert.deepEqual(findProblems({ direction: "LR", boxes: [], edges }), []);
});

test("flags the failures seen in the 9B holdout runs", () => {
  const edges: [string, string, string][] = [
    ["Recruiter", "Resume match?", ""],
    ["Resume match?", "Hiring manager", "yes"],
    ["Resume match?", "Hiring manager", "no"],
    ["Customs", "Depot", "inspects"],
  ];
  assert.deepEqual(findProblems({ direction: "LR", boxes: ["Locker"], edges }), [
    '"Locker" is not connected',
    '"Resume match?" sends yes and no to the same box',
    'nothing leads into "Customs"',
  ]);
});

test("flags an 'otherwise' sentence that leaves a decision with one outcome", () => {
  const before = { direction: "LR" as const, boxes: ["Decoder"], edges: [] };
  const sentence = "the decoder drops a frame if the checksum fails, otherwise it writes it to the database.";
  const oneOutcome = { ...before, edges: [["Decoder", "Checksum failed?", ""], ["Checksum failed?", "Frame Log", "yes"]] as [string, string, string][] };
  const bothOutcomes = { ...before, edges: [...oneOutcome.edges, ["Checksum failed?", "Database", "no"]] as [string, string, string][] };
  assert.deepEqual(findStepProblems(before, sentence, oneOutcome), ['"Checksum failed?" has one outcome, but the sentence says what happens otherwise']);
  assert.deepEqual(findStepProblems(before, sentence, bothOutcomes), []);
  assert.deepEqual(findStepProblems(before, sentence, before), ["the sentence says what happens otherwise, but no decision gets an outcome"]);
  assert.deepEqual(findStepProblems(before, "the walk-in goes on to the id check like everyone else.", before), []);
});
