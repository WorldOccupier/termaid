import assert from "node:assert/strict";
import { test } from "node:test";
import { OllamaClient } from "../src/ollamaClient.ts";

test("disables thinking so thinking-template models reply with JSON content", async () => {
  let sentBody: Record<string, unknown> = {};
  const fakeFetch = (async (_url: string, init: RequestInit) => {
    sentBody = JSON.parse(init.body as string);
    return new Response(JSON.stringify({ message: { content: '{"boxes": []}' } }));
  }) as typeof fetch;

  const reply = await new OllamaClient("http://ollama", "termaid-lfm3", fakeFetch).completeJson("system", "user", {});

  assert.equal(sentBody.think, false);
  assert.deepEqual(reply, { boxes: [] });
});
