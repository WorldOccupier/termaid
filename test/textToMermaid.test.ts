import { test } from "node:test";
import assert from "node:assert/strict";
import { TextToMermaid } from "../src/textToMermaid.ts";
import type { JsonCompletionClient } from "../src/ollamaClient.ts";
import { PeleRenderer } from "../src/peleRenderer.ts";

function convertReply(reply: unknown): Promise<string> {
  const fakeClient: JsonCompletionClient = { completeJson: async () => reply };
  return new TextToMermaid(fakeClient, new PeleRenderer()).convert("any description");
}

test("converts edge tuples into a Mermaid flowchart, merging boxes with the same name and avoiding keywords", async () => {
  const mermaid = await convertReply({
    direction: "LR",
    edges: [
      ["Web App", 'The "main" DB', "reads"],
      ["web  app", "1st-cache", "writes"],
      ["1st-cache", "End", "expires"],
    ],
  });

  assert.equal(
    mermaid,
    'flowchart LR\n  n_web_app["Web App"]\n  n_the__main__db["The #quot;main#quot; DB"]\n  n_1st_cache["1st-cache"]\n' +
      '  n_end["End"]\n  n_web_app -->|"reads"| n_the__main__db\n  n_web_app -->|"writes"| n_1st_cache\n' +
      '  n_1st_cache -->|"expires"| n_end\n',
  );
});

test("drops malformed edges and strips condition clauses from labels", async () => {
  const mermaid = await convertReply({
    direction: "sideways",
    edges: [["", "B", "x"], "junk", ["A", "B", "returns token if valid"], ["B", "A", "reads from only if cache misses"]],
  });

  assert.equal(mermaid, 'flowchart LR\n  n_a["A"]\n  n_b["B"]\n  n_a -->|"returns token"| n_b\n  n_b -->|"reads from"| n_a\n');
});

test("keeps listed boxes that no edge connects", async () => {
  const mermaid = await convertReply({ direction: "LR", boxes: ["API", "Cache"], edges: [["API", "DB", "calls"]] });

  assert.equal(
    mermaid,
    'flowchart LR\n  n_api["API"]\n  n_cache["Cache"]\n  n_db["DB"]\n  n_api -->|"calls"| n_db\n',
  );
});

test("renders boxes ending in a question mark as decision diamonds", async () => {
  const mermaid = await convertReply({
    direction: "LR",
    boxes: ["API", "Cache miss?", "Database"],
    edges: [["API", "Cache miss?", ""], ["Cache miss?", "Database", "yes"]],
  });

  assert.equal(
    mermaid,
    'flowchart LR\n  n_api["API"]\n  n_cache_miss_{"Cache miss?"}\n  n_database["Database"]\n' +
      '  n_api --> n_cache_miss_\n  n_cache_miss_ -->|"yes"| n_database\n',
  );
});

test("updates the diagram one sentence at a time, sending the previous state with each sentence", async () => {
  const replies = [
    { direction: "LR", boxes: ["User", "API"], edges: [["User", "API", "calls"]] },
    { direction: "LR", boxes: ["User", "Gateway", "API"], edges: [["User", "Gateway", "calls"], ["Gateway", "API", "routes to"]] },
  ];
  const requests: string[] = [];
  const recordingClient: JsonCompletionClient = {
    completeJson: async (_system, request) => {
      requests.push(request);
      return replies[requests.length - 1];
    },
  };

  const mermaid = await new TextToMermaid(recordingClient, new PeleRenderer()).convert(
    "The user calls the API. There is a gateway in front of the API.",
  );

  assert.deepEqual(requests, [
    'Diagram so far: {"direction":"LR","boxes":[],"edges":[]}\nNext sentence: The user calls the API.',
    'Diagram so far: {"direction":"LR","boxes":["User","API"],"edges":[["User","API","calls"]]}\n' +
      "Next sentence: There is a gateway in front of the API.",
  ]);
  assert.match(mermaid, /n_gateway -->\|"routes to"\| n_api/);
});
