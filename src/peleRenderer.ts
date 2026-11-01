import { parse, render, PeleError } from "pele";

export type RenderOptions = Parameters<typeof render>[1];

export interface MermaidRenderer {
  validate(mermaid: string): void;
  toSvg(mermaid: string, options?: RenderOptions): string;
}

export class InvalidMermaidError extends Error {}

export class PeleRenderer implements MermaidRenderer {
  validate(mermaid: string): void {
    this.withReadableErrors(() => parse(mermaid));
  }

  toSvg(mermaid: string, options?: RenderOptions): string {
    return this.withReadableErrors(() => render(mermaid, options).svg);
  }

  private withReadableErrors<T>(action: () => T): T {
    try {
      return action();
    } catch (error) {
      if (error instanceof PeleError) {
        throw new InvalidMermaidError(`Generated Mermaid is invalid (${error.code}): ${error.message}`);
      }
      throw error;
    }
  }
}
