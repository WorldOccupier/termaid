// Scores `termaid-mac eval` JSON lines with the repo's own structural checks.
// usage: node training/weight_space/score.ts <tag> [baseline-tag]   (reads weight_space/results/<tag>-<holdout>.jsonl)
import { readFileSync } from "node:fs";
import { findProblems } from "../../src/diagramCheck.ts";
import type { DiagramState } from "../../src/diagramState.ts";

const FILES = ["holdout", "holdout-complex", "holdout-complex-2", "holdout-front"];
const CONDITION = /\b(if|when|unless|otherwise|else|fall(s|ing)? back|on a miss)\b/i;

interface Row { description: string; state?: DiagramState; error?: string }

// A tag ending in ".jsonl" is read as one file (e.g. pipeline.py output on the dev split).
function load(tag: string, file: string): Row[] {
  const path = tag.endsWith(".jsonl") ? tag : new URL(`results/${tag}-${file}.jsonl`, import.meta.url);
  return readFileSync(path, "utf8").split("\n").filter(Boolean).map((line) => JSON.parse(line));
}

function decisions(state: DiagramState) {
  const boxes = new Set([...state.boxes, ...state.edges.flatMap(([a, b]) => [a, b])]);
  const ds = [...boxes].filter((b) => b.endsWith("?"));
  const full = ds.filter((d) => {
    const labels = state.edges.filter(([from]) => from === d).map(([, , l]) => l);
    return labels.includes("yes") && labels.includes("no");
  });
  return { total: ds.length, full: full.length };
}

function score(rows: Row[]) {
  const s = { n: rows.length, valid: 0, clean: 0, problems: 0, decisions: 0, fullDecisions: 0, missingDecision: 0, edges: 0 };
  for (const row of rows) {
    if (!row.state) continue;
    s.valid++;
    const problems = findProblems(row.state);
    s.problems += problems.length;
    if (problems.length === 0) s.clean++;
    const d = decisions(row.state);
    s.decisions += d.total;
    s.fullDecisions += d.full;
    if (CONDITION.test(row.description) && d.total === 0) s.missingDecision++;
    s.edges += row.state.edges.length;
  }
  return s;
}

const key = (state?: DiagramState) => JSON.stringify(state ?? null);
const [tag, base] = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const total: Record<string, number> = {};
const files = tag.endsWith(".jsonl") ? ["file"] : FILES;
for (const file of files) {
  const rows = load(tag, file);
  const s: Record<string, number> = score(rows);
  if (base) {
    const baseRows = load(base, file);
    s.sameAsBase = rows.filter((r, i) => key(r.state) === key(baseRows[i]?.state)).length;
  }
  for (const [k, v] of Object.entries(s)) total[k] = (total[k] ?? 0) + v;
  console.log(file.padEnd(18), JSON.stringify(s));
}
console.log("TOTAL".padEnd(18), JSON.stringify(total));
if (process.argv.includes("--errors")) {
  for (const file of files) for (const r of load(tag, file)) {
    if (r.error) console.log(`ERROR [${file}] ${r.error} :: ${r.description.slice(0, 90)}`);
    else for (const p of findProblems(r.state!)) console.log(`PROBLEM [${file}] ${p} :: ${r.description.slice(0, 90)}`);
  }
}
