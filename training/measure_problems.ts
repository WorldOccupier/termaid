// Runs the app's findProblems checks over training rows and reports how often the gold diagrams break them.
// A row is "final" when its answer is never the "Diagram so far" of another row, i.e. the finished diagram.
// usage: node training/measure_problems.ts <rows.jsonl>... [--list <out.jsonl>]
import { readFileSync, writeFileSync } from "node:fs";
import { findProblems, findStepProblems } from "../src/diagramCheck.ts";
import type { DiagramState } from "../src/diagramState.ts";

interface Row { file: string; line: number; sentence: string; before: DiagramState; after: DiagramState }

const SO_FAR = /^Diagram so far: (.*)$/m;
const SENTENCE = /^Next sentence: (.*)$/m;

function loadRows(file: string): Row[] {
  return readFileSync(file, "utf8").split("\n").filter(Boolean).map((text, index) => {
    const messages = JSON.parse(text).messages;
    const user = messages.findLast((m: { role: string }) => m.role === "user").content;
    const answer = messages.findLast((m: { role: string }) => m.role === "assistant").content;
    return { file, line: index + 1, sentence: user.match(SENTENCE)?.[1] ?? "", before: JSON.parse(user.match(SO_FAR)[1]), after: JSON.parse(answer) };
  });
}

const canonical = (state: DiagramState) => JSON.stringify([state.boxes, state.edges]);

// Problems already present in the diagram before this row are not this row's fault.
// findStepProblems adds what the sentence asked for but the step left out (an "otherwise" outcome).
function newProblems(row: Row): string[] {
  const existing = new Set(findProblems(row.before));
  const structural = findProblems(row.after).filter((problem) => !existing.has(problem));
  return [...structural, ...findStepProblems(row.before, row.sentence, row.after)];
}

function kind(problem: string): string {
  return problem.replace(/"[^"]*"/g, "X");
}

function tally(problems: string[][]): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const problem of problems.flat()) counts[kind(problem)] = (counts[kind(problem)] ?? 0) + 1;
  return counts;
}

function report(label: string, rows: Row[], problemsOf: (row: Row) => string[]) {
  const problems = rows.map(problemsOf);
  const flagged = problems.filter((list) => list.length > 0).length;
  console.log(`${label}: ${flagged} of ${rows.length} flagged (${((100 * flagged) / rows.length).toFixed(1)}%)`);
  for (const [name, count] of Object.entries(tally(problems)).sort((a, b) => b[1] - a[1])) console.log(`  ${String(count).padStart(5)}  ${name}`);
}

const args = process.argv.slice(2);
const listAt = args.indexOf("--list");
const listPath = listAt >= 0 ? args[listAt + 1] : undefined;
const files = args.filter((arg, i) => !arg.startsWith("--") && (listAt < 0 || i !== listAt + 1));
const rows = files.flatMap(loadRows);
const intermediate = new Set(rows.map((row) => canonical(row.before)));
const finals = rows.filter((row) => !intermediate.has(canonical(row.after)));

report("Rows (problems the step introduced)", rows, newProblems);
report("Finished diagrams (all problems)", finals, (row) => findProblems(row.after));

if (listPath) {
  const flagged = rows.map((row) => ({ file: row.file, line: row.line, sentence: row.sentence, problems: newProblems(row) }))
    .filter((entry) => entry.problems.length > 0);
  writeFileSync(listPath, flagged.map((entry) => JSON.stringify(entry)).join("\n") + "\n");
  console.log(`Wrote ${flagged.length} flagged rows to ${listPath}`);
}
