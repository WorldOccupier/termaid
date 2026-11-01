// Runs held-out descriptions through the app's own pipeline (checks and retries included) and
// prints them like eval_ollama.py, plus any problems left in the kept diagram.
// Usage: node training/eval_termaid.ts <ollama model> <descriptions.txt> [attempts]   (needs `ollama serve`)
import { readFile } from "node:fs/promises";
import { findProblems } from "../src/diagramCheck.ts";
import { OllamaClient } from "../src/ollamaClient.ts";
import { PeleRenderer } from "../src/peleRenderer.ts";
import { TextToMermaid } from "../src/textToMermaid.ts";

const [model, descriptionsFile, attempts = "3"] = process.argv.slice(2);
const client = new OllamaClient(process.env.OLLAMA_URL ?? "http://localhost:11434", model);
const converter = new TextToMermaid(client, new PeleRenderer(), "whole-text", Number(attempts));

console.log(`######## ${model} (attempts ${attempts})`);
for (const description of (await readFile(descriptionsFile, "utf8")).split("\n").filter(Boolean)) {
  const start = performance.now();
  const state = await converter.describe(description).catch((error: Error) => ({ edges: [], boxes: [], direction: "LR" as const, error }));
  console.log(`== ${description}  (${((performance.now() - start) / 1000).toFixed(2)}s)`);
  if ("error" in state) console.log(`  INVALID: ${state.error.message}`);
  for (const [from, to, label] of state.edges) console.log(`  ${from} --${label}--> ${to}`);
  for (const problem of findProblems(state)) console.log(`  !! ${problem}`);
}
