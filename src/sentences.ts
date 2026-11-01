// Keep in sync with SENTENCE_BREAK in training/story.py: the model is trained on these splits.
const SENTENCE_BREAK = /(?<=[.!?])\s+|\n+/;

export function splitSentences(text: string): string[] {
  return text
    .split(SENTENCE_BREAK)
    .map((sentence) => sentence.trim())
    .filter((sentence) => sentence.length > 0);
}
