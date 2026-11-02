import { test } from "node:test";
import assert from "node:assert/strict";
import { convert, convertSteps, editSteps, sentences, toSvg } from "../src/embeddedEngine.ts";
import type { HostCompletion } from "../src/hostCompletionClient.ts";

function fakeHost(replies: unknown[]): HostCompletion {
  let call = 0;
  return async () => JSON.stringify(replies[call++]);
}

const replies = [
  { direction: "LR", boxes: ["User", "API"], edges: [["User", "API", "calls"]] },
  { direction: "LR", boxes: ["User", "Gateway", "API"], edges: [["User", "Gateway", "calls"], ["Gateway", "API", "routes to"]] },
];
const description = "The user calls the API. There is a gateway in front of the API.";

test("sentences returns the split sentences as a JSON array", () => {
  assert.deepEqual(JSON.parse(sentences(description)), [
    "The user calls the API.",
    "There is a gateway in front of the API.",
  ]);
});

test("convertSteps calls onStep once per sentence with the SVG of the diagram so far", async () => {
  const steps: [number, string][] = [];
  await convertSteps(description, fakeHost(replies), (index, svg) => steps.push([index, svg]));

  assert.deepEqual(steps.map(([index]) => index), [0, 1]);
  assert.equal(steps[0][1], toSvg('flowchart LR\n  n_user["User"]\n  n_api["API"]\n  n_user -->|"calls"| n_api\n'));
  assert.match(steps[1][1], /<svg/);
  assert.notEqual(steps[0][1], steps[1][1]);
});

test("convertSteps resolves with the same Mermaid as convert", async () => {
  const streamed = await convertSteps(description, fakeHost(replies), () => {});
  const plain = await convert(description, fakeHost(replies));

  assert.equal(streamed, plain);
  assert.match(streamed, /n_gateway -->\|"routes to"\| n_api/);
});

test("editSteps starts the model from the saved diagram and returns the edited Mermaid", async () => {
  const saved = await convert("The user calls the API.", fakeHost([replies[0]]));
  const requests: string[] = [];
  const host: HostCompletion = async (_system, user) => {
    requests.push(user);
    return JSON.stringify(replies[1]);
  };

  const edited = await editSteps(saved, "Put a gateway in front of the API.", host, () => {});

  assert.ok(requests[0].includes(JSON.stringify(replies[0])));
  assert.match(edited, /n_gateway -->\|"routes to"\| n_api/);
});

test("editSteps switches the layout direction without asking the model", async () => {
  const saved = await convert("The user calls the API.", fakeHost([replies[0]]));
  const host: HostCompletion = async () => assert.fail("the model should not be called");

  const edited = await editSteps(saved, "Make it top to bottom.", host, () => {});

  assert.match(edited, /^flowchart TD/);
  assert.match(edited, /n_user -->\|"calls"\| n_api/);
});
