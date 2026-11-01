"""Turn grok's whole-description examples into per-sentence training steps.

The default app mode sends one sentence at a time with the diagram so far, but the grok examples
(grok_label.py) only teach whole descriptions. Grok replays each description sentence by sentence;
a replay is kept only if every step passes the diagram rules and the last step matches its own
final diagram, so the steps can't drift from the labels that already passed the checks.

Usage: grok_steps.py <grok.jsonl> <output.jsonl>   (records use the PER_SENTENCE prompt)
"""

import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from generate_data import load_system_prompt, to_chat_record
from grok_label import PARALLEL_CALLS, diagram_problem
from story import split_sentences

DIAGRAM = {"type": "object", "required": ["direction", "boxes", "edges"], "properties": {
    "direction": {"type": "string", "enum": ["TD", "LR"]},
    "boxes": {"type": "array", "items": {"type": "string"}},
    "edges": {"type": "array", "items": {"type": "array", "items": {"type": "string"}}}}}
REPLY_SCHEMA = {"type": "object", "required": ["steps"], "properties": {"steps": {"type": "array", "items": DIAGRAM}}}

INSTRUCTIONS = """A flowchart is built one sentence at a time. Below are the sentences of a description and
the final diagram. Give the diagram after each sentence: {count} diagrams, the last one exactly equal
to the final diagram. Each diagram includes everything from earlier sentences, updated by that sentence
only (a later sentence may re-route earlier edges, e.g. putting a box in front of another). Use the same
box names and edge labels as the final diagram and follow these rules:
{rules}

Sentences:
{sentences}

Final diagram: {final}

Answer directly from these instructions; do not use any tools or look at files.
Reply with only JSON: {{"steps": [<diagram after sentence 1>, ...]}}"""


def ask_grok_steps(prompt: str) -> list[dict]:
    completed = subprocess.run(["grok", "-p", prompt, "--disable-web-search", "--json-schema", json.dumps(REPLY_SCHEMA)],
                               capture_output=True, text=True, timeout=600, cwd="/tmp")
    try:
        return json.loads(json.loads(completed.stdout)["text"])["steps"]
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError):
        return []


def normalized(diagram: dict) -> dict:
    return {"direction": diagram["direction"], "boxes": list(diagram["boxes"]), "edges": [list(e) for e in diagram["edges"]]}


def steps_problem(steps: list[dict], sentences: list[str], final: dict) -> str | None:
    """Why a replay can't be used, or None when it can."""
    if len(steps) != len(sentences):
        return "step count"
    if any(diagram_problem(step) for step in steps):
        return "step breaks rules"
    if normalized(steps[-1]) != normalized(final):
        return "last step differs"
    return None


def replay_records(system_prompt: str, sentences: list[str], steps: list[dict]) -> list[dict]:
    # The app's empty diagram is LR; later steps keep grok's direction.
    before = {"direction": "LR", "boxes": [], "edges": []}
    records = []
    for sentence, step in zip(sentences, steps):
        after = normalized(step)
        records.append(to_chat_record(system_prompt, before, sentence, after))
        before = after
    return records


def main() -> None:
    from grok_label import diagram_rules
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    examples = [json.loads(line) for line in source.read_text().splitlines()]
    system_prompt, rules = load_system_prompt(), diagram_rules()
    jobs = []
    for example in examples:
        sentences = split_sentences(example["description"])
        prompt = INSTRUCTIONS.format(count=len(sentences), rules=rules, final=json.dumps(example["diagram"]),
                                     sentences="\n".join(f"{i}. {s}" for i, s in enumerate(sentences, 1)))
        jobs.append((sentences, example["diagram"], prompt))
    kept, rejected = 0, {}
    # Each replay is saved as it arrives, so stopping early keeps the finished calls.
    with ThreadPoolExecutor(PARALLEL_CALLS) as pool, output.open("a") as out:
        futures = {pool.submit(ask_grok_steps, prompt): (sentences, final) for sentences, final, prompt in jobs}
        for done, future in enumerate(as_completed(futures), 1):
            sentences, final = futures[future]
            steps = future.result()
            reason = steps_problem(steps, sentences, final)
            if reason:
                rejected[reason] = rejected.get(reason, 0) + 1
            else:
                records = replay_records(system_prompt, sentences, steps)
                out.writelines(json.dumps(record) + "\n" for record in records)
                out.flush()
                kept += len(records)
            print(f"{done}/{len(jobs)}: {kept} steps kept, rejected {rejected}", flush=True)


if __name__ == "__main__":
    main()
