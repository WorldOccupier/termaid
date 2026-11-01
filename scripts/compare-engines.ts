// Checks that the Swift llama.cpp engine draws diagrams as well as the Ollama path. Exact matches
// are reported but not required: the two runtimes' arithmetic differs slightly, which flips
// near-tied tokens ("S3 down?" vs "S3 unavailable?"), so quality is judged by findProblems.
// Usage: node scripts/compare-engines.ts <swift-results.jsonl> <descriptions.txt>...   (needs `ollama serve`)
import { readFile } from "node:fs/promises";
import { isDeepStrictEqual } from "node:util";
import { findProblems } from "../src/diagramCheck.ts";
import type { DiagramState } from "../src/diagramState.ts";
import { OllamaClient } from "../src/ollamaClient.ts";
import { PeleRenderer } from "../src/peleRenderer.ts";
import { TextToMermaid } from "../src/textToMermaid.ts";

// Swift may leave at most this many more problems than Ollama across the whole set.
const PROBLEM_TOLERANCE = 1.1;
const MAX_DESCRIPTION_CHARS = 60;

interface SwiftLine {
  description: string;
  state?: DiagramState;
  error?: string;
  seconds: number;
}

// One engine's answer for a description: a diagram, or the error that replaced it.
interface Side {
  state?: DiagramState;
  error?: string;
  seconds: number;
}

interface Row {
  description: string;
  ollama: Side;
  swift: Side;
  match: boolean;
}

async function main(): Promise<void> {
  const [swiftFile, ...descriptionFiles] = process.argv.slice(2);
  if (!swiftFile || descriptionFiles.length === 0) {
    throw new Error("usage: compare-engines.ts <swift-results.jsonl> <descriptions.txt>...");
  }
  const swiftByDescription = await loadSwiftResults(swiftFile);
  const descriptions = await readDescriptions(descriptionFiles);
  const pairs = descriptions.map((description) => ({ description, swift: findSwift(swiftByDescription, description) }));

  const converter = new TextToMermaid(
    new OllamaClient(process.env.OLLAMA_URL ?? "http://localhost:11434", process.env.TERMAID_MODEL ?? "termaid-lfm3"),
    new PeleRenderer(),
  );
  // Rows print as they finish, so a run stopped partway still shows its results.
  printTableHeader();
  const rows: Row[] = [];
  for (const { description, swift } of pairs) {
    const ollama = await runOllama(converter, description);
    const swiftSide = toSide(swift);
    rows.push({ description, ollama, swift: swiftSide, match: sameDiagram(ollama.state, swiftSide.state) });
    printTableRow(rows.at(-1)!, rows.length);
  }
  printDetails(rows);
}

async function loadSwiftResults(file: string): Promise<Map<string, SwiftLine>> {
  const lines = nonEmptyLines(await readFile(file, "utf8"));
  return new Map(lines.map((line): [string, SwiftLine] => {
    const result = JSON.parse(line) as SwiftLine;
    return [result.description, result];
  }));
}

async function readDescriptions(files: string[]): Promise<string[]> {
  const texts = await Promise.all(files.map((file) => readFile(file, "utf8")));
  return texts.flatMap(nonEmptyLines);
}

function nonEmptyLines(text: string): string[] {
  return text.split("\n").filter((line) => line.trim() !== "");
}

function findSwift(swiftByDescription: Map<string, SwiftLine>, description: string): SwiftLine {
  const result = swiftByDescription.get(description);
  if (!result) throw new Error(`missing Swift result for description: "${description}"`);
  return result;
}

function toSide(line: SwiftLine): Side {
  const state = line.state ? comparable(line.state) : undefined;
  return { state, error: line.error ?? (state ? undefined : "no state in Swift result"), seconds: line.seconds };
}

async function runOllama(converter: TextToMermaid, description: string): Promise<Side> {
  const start = performance.now();
  try {
    return { state: comparable(await converter.describe(description)), seconds: elapsedSince(start) };
  } catch (error) {
    return { error: (error as Error).message, seconds: elapsedSince(start) };
  }
}

function elapsedSince(start: number): number {
  return (performance.now() - start) / 1000;
}

// Only the fields both engines are compared on, so extra keys in a result never count.
function comparable(state: DiagramState): DiagramState {
  return { direction: state.direction, boxes: state.boxes, edges: state.edges };
}

function sameDiagram(a: DiagramState | undefined, b: DiagramState | undefined): boolean {
  return a !== undefined && b !== undefined && isDeepStrictEqual(a, b);
}

function problemsOf(side: Side): string[] {
  return side.state ? findProblems(side.state) : [];
}

function printTableHeader(): void {
  console.log("| # | Match | Ollama s | Swift s | Description |");
  console.log("|---|---|---|---|---|");
}

function printTableRow(row: Row, number: number): void {
  const cells = [number, row.match ? "✅" : "❌", row.ollama.seconds.toFixed(2), row.swift.seconds.toFixed(2), truncate(row.description)];
  console.log(`| ${cells.join(" | ")} |`);
}

function printDetails(rows: Row[]): void {
  rows.filter((row) => !row.match).forEach((row) => printMismatch(row, rows.indexOf(row) + 1));
  printSummary(rows);
}

function truncate(description: string): string {
  const short = description.length > MAX_DESCRIPTION_CHARS ? `${description.slice(0, MAX_DESCRIPTION_CHARS - 3)}...` : description;
  return short.replaceAll("|", "\\|");
}

function printMismatch(row: Row, number: number): void {
  console.log(`\n#${number} ${row.description}`);
  printSide("Ollama", row.ollama);
  printSide("Swift", row.swift);
}

function printSide(name: string, side: Side): void {
  console.log(`  ${name}:`);
  if (side.error) console.log(`    error: ${side.error}`);
  for (const [from, to, label] of side.state?.edges ?? []) console.log(`    ${from} --${label}--> ${to}`);
  for (const problem of problemsOf(side)) console.log(`    !! ${problem}`);
}

function printSummary(rows: Row[]): void {
  const matched = rows.filter((row) => row.match).length;
  const ollamaProblems = rows.reduce((sum, row) => sum + problemsOf(row.ollama).length, 0);
  const swiftProblems = rows.reduce((sum, row) => sum + problemsOf(row.swift).length, 0);
  console.log(`\nmatched ${matched}/${rows.length}, Ollama problems: ${ollamaProblems}, Swift problems: ${swiftProblems}`);
  const swiftErrors = rows.filter((row) => row.swift.error !== undefined).length;
  if (swiftErrors > 0) console.log(`Swift errors: ${swiftErrors}`);
  process.exitCode = swiftErrors > 0 || swiftProblems > ollamaProblems * PROBLEM_TOLERANCE ? 1 : 0;
}

try {
  await main();
} catch (error) {
  console.error(`compare-engines: ${(error as Error).message}`);
  process.exitCode = 1;
}
