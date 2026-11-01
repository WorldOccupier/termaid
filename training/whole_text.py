"""Whole-description data: one record per story, the full description in and the final diagram out.

The per-sentence data keeps each story's steps in order, starting from an empty diagram, so a story
is the run of records from one empty "Diagram so far" to the next. Matches TextToMermaid.convert
without --per-sentence (WHOLE_TEXT_PROMPT, description as the user message).

Usage: whole_text.py <per-sentence data dir> <output dir>
"""

import json
import subprocess
import sys
from pathlib import Path

from generate_data import REPO_DIR

EMPTY_REQUEST_PREFIX = 'Diagram so far: {"direction":"LR","boxes":[],"edges":[]}\n'


def load_whole_text_prompt() -> str:
    script = 'import("./src/textToMermaid.ts").then((m) => process.stdout.write(m.WHOLE_TEXT_PROMPT))'
    return subprocess.run(["node", "-e", script], cwd=REPO_DIR, check=True, capture_output=True, text=True).stdout


def to_stories(records: list[dict]) -> list[tuple[str, str]]:
    stories = []
    for record in records:
        _, request, reply = record["messages"]
        sentence = request["content"].split("\nNext sentence: ", 1)[1]
        if request["content"].startswith(EMPTY_REQUEST_PREFIX):
            stories.append([[], None])
        stories[-1][0].append(sentence)
        stories[-1][1] = reply["content"]
    return [(" ".join(sentences), diagram) for sentences, diagram in stories]


def main() -> None:
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    output.mkdir(exist_ok=True)
    prompt = load_whole_text_prompt()
    for name in ["train.jsonl", "valid.jsonl"]:
        records = [json.loads(line) for line in (source / name).read_text().splitlines()]
        stories = to_stories(records)
        (output / name).write_text("".join(json.dumps({"messages": [
            {"role": "system", "content": prompt}, {"role": "user", "content": description},
            {"role": "assistant", "content": diagram}]}) + "\n" for description, diagram in stories))
        print(f"{name}: {len(stories)} descriptions")


if __name__ == "__main__":
    main()
