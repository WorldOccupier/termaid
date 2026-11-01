import { test } from "node:test";
import assert from "node:assert/strict";
import { findProblems } from "../src/diagramCheck.ts";

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
