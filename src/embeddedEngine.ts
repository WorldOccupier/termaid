// Entry point bundled into dist/engine.js for native apps that run termaid's engine in a
// JavaScript runtime (JavaScriptCore on macOS) and supply the model themselves.
import { type HostCompletion, HostCompletionClient } from "./hostCompletionClient.ts";
import { OBSIDIAN } from "./obsidianTheme.ts";
import { PeleRenderer } from "./peleRenderer.ts";
import { splitSentences } from "./sentences.ts";
import { flattenCssVariables } from "./svgFlattener.ts";
import { styled } from "./svgStyler.ts";
import { TextToMermaid } from "./textToMermaid.ts";

const renderer = new PeleRenderer();
// The look the mockups use (scripts/render-mockup-diagrams.ts).
const APP_LAYOUT = { fontSize: 18, config: { flowchart: { nodeSpacing: 28, rankSpacing: 36 } } };

// Themed, with every CSS variable resolved: macOS's SVG renderer ignores them, so a raw Pele SVG
// draws as black boxes.
function appSvg(mermaid: string): string {
  return flattenCssVariables(styled(renderer.toSvg(mermaid, APP_LAYOUT), OBSIDIAN, { pad: 24 }));
}

function converter(complete: HostCompletion): TextToMermaid {
  return new TextToMermaid(new HostCompletionClient(complete), renderer);
}

export function convert(description: string, complete: HostCompletion): Promise<string> {
  return converter(complete).convert(description);
}

// Runs the per-sentence loop; after each sentence, onStep gets the SVG of the diagram so far.
// A step that fails to render is skipped; the final result is still validated like `convert`.
export async function convertSteps(
  description: string,
  complete: HostCompletion,
  onStep: (index: number, svg: string) => void,
): Promise<string> {
  const state = await converter(complete).describe(description, (index, step) => {
    let svg: string;
    try {
      svg = appSvg(TextToMermaid.mermaidFor(step));
    } catch {
      return;
    }
    onStep(index, svg);
  });
  const mermaid = TextToMermaid.mermaidFor(state);
  renderer.validate(mermaid);
  return mermaid;
}

export function sentences(description: string): string {
  return JSON.stringify(splitSentences(description));
}

export async function describe(description: string, complete: HostCompletion): Promise<string> {
  return JSON.stringify(await converter(complete).describe(description));
}

export function toSvg(mermaid: string): string {
  return appSvg(mermaid);
}
