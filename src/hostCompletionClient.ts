import type { JsonCompletionClient } from "./ollamaClient.ts";

// Supplied by the native app that embeds the engine; it runs the model and resolves with the raw reply.
export type HostCompletion = (systemPrompt: string, userPrompt: string) => Promise<string>;

// The host constrains output with its own grammar for the reply shape, so the schema isn't forwarded.
export class HostCompletionClient implements JsonCompletionClient {
  private readonly complete: HostCompletion;

  constructor(complete: HostCompletion) {
    this.complete = complete;
  }

  async completeJson(systemPrompt: string, userPrompt: string, _schema: object): Promise<unknown> {
    return JSON.parse(await this.complete(systemPrompt, userPrompt));
  }
}
