// Dictation comes in bursts; keep the model in memory so a run never pays the reload cost.
const KEEP_MODEL_LOADED_FOR = "30m";
// The largest holdout diagrams need about 400 tokens. A model stuck repeating edges otherwise runs
// for minutes until Ollama's context fills, so the reply is cut off and fails to parse.
const MAX_REPLY_TOKENS = 1000;

export interface JsonCompletionClient {
  completeJson(systemPrompt: string, userPrompt: string, schema: object): Promise<unknown>;
}

export class OllamaClient implements JsonCompletionClient {
  private readonly baseUrl: string;
  private readonly model: string;
  private readonly fetchFn: typeof fetch;

  constructor(baseUrl: string, model: string, fetchFn: typeof fetch = fetch) {
    this.baseUrl = baseUrl;
    this.model = model;
    this.fetchFn = fetchFn;
  }

  async completeJson(systemPrompt: string, userPrompt: string, schema: object): Promise<unknown> {
    const response = await this.fetchFn(`${this.baseUrl}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.model,
        stream: false,
        keep_alive: KEEP_MODEL_LOADED_FOR,
        // Models with a thinking template (LFM3, Qwen3.5) otherwise reason in free text until
        // MAX_REPLY_TOKENS and return empty content. Models without one ignore this.
        think: false,
        format: schema,
        options: { temperature: 0, num_predict: MAX_REPLY_TOKENS },
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
      }),
    });
    if (!response.ok) {
      throw new Error(`Ollama request failed (${response.status}): ${await response.text()}`);
    }
    const body = (await response.json()) as { message: { content: string } };
    return JSON.parse(body.message.content);
  }
}
