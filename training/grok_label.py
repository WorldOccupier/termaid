"""Complex whole-description examples written and labelled by grok, filtered by structural checks.

The template stories (story.py) only phrase things the templates know, so the models miss which box
asks a question, which way yes/no go, and "in front of" routing in free-form text. Grok writes
realistic multi-step descriptions with their diagrams; checks drop diagrams that break the rules.
The holdout topics are excluded so the eval stays honest.

Usage: grok_label.py <calls> <whole-text data dir to mix in> <output dir>   (5 descriptions per call)
"""

import json
import random
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from whole_text import load_whole_text_prompt

PER_CALL = 5
PARALLEL_CALLS = 15
EDGE = {"type": "array", "items": {"type": "string"}}
REPLY_SCHEMA = {"type": "object", "required": ["examples"], "properties": {"examples": {"type": "array", "items": {
    "type": "object", "required": ["description", "diagram"], "properties": {
        "description": {"type": "string"},
        "diagram": {"type": "object", "required": ["direction", "boxes", "edges"], "properties": {
            "direction": {"type": "string", "enum": ["TD", "LR"]},
            "boxes": {"type": "array", "items": {"type": "string"}},
            "edges": {"type": "array", "items": EDGE}}}}}}}}
CONDITION_WORD = re.compile(r"\b(if|when|unless|otherwise|else)\b", re.I)

# No hiring, clinics, parcels, schools, law firms, factories or video: those are the holdout.
# Nor the domains in holdout-complex-2.txt (blood donation, juries, ports, 911, tax, payroll, ...).
TOPICS = [
    "restaurant kitchen orders", "airport baggage handling", "bank loan approval", "insurance claims",
    "library book lending", "car rental returns", "hotel check-in", "food delivery app", "ride sharing",
    "online store checkout", "warehouse returns", "IT helpdesk tickets", "software release pipeline",
    "payment fraud detection", "email newsletter sending", "IoT sensor alerts", "log ingestion pipeline",
    "search indexing", "chat app messaging", "photo upload and resizing", "DNS and web hosting",
    "mobile game matchmaking", "stock trading orders", "subscription billing", "event ticketing",
    "airline check-in", "vet appointment booking", "real estate mortgage", "grant applications",
    "city permit requests", "restaurant reservations", "gym membership signup", "car repair shop",
    "farm irrigation", "power grid monitoring", "museum ticketing", "conference talk submissions",
    "open source pull requests", "data warehouse ETL", "machine learning model training",
    "recycling collection", "pizza delivery", "bike sharing", "travel visa applications",
    "charity donations", "podcast publishing", "smart home automation", "customer support chat",
]

INSTRUCTIONS = """Write {count} training examples for a model that turns plain-English descriptions into flowcharts.
Topics, one each: {topics}.

Each description: 4-6 sentences of natural, varied English, like a person explaining a process or system
(lowercase, run-on sentences and a typo are fine). Each one must include:
- 2 or 3 conditions phrased differently ("if ... otherwise", "only when", "falling back to ... when",
  "unless", "on a miss", "else"). Make the box that CHECKS the condition differ from the boxes that act
  in each case, e.g. "if the panel approves, HR makes an offer, else the manager sends it back".
- at least one step that loops back to an earlier box ("sends it back to", "retries").
- in about half: "X sits in front of Y" / "there is an X before Y", or "Y is replicated/multiple and
  uses round robin / least connections".

The diagram for each follows these rules exactly:
{rules}

Answer directly from these instructions; do not use any tools or look at files.
Reply with only JSON: {{"examples": [{{"description": "...", "diagram": {{"direction": ..., "boxes": [...], "edges": [...]}}}}, ...]}}"""


def diagram_rules() -> str:
    prompt = load_whole_text_prompt()
    return prompt[prompt.index("Reply with JSON"):prompt.index("Example input")].strip()


def ask_grok(prompt: str) -> list[dict]:
    completed = subprocess.run(["grok", "-p", prompt, "--disable-web-search", "--json-schema", json.dumps(REPLY_SCHEMA)],
                               capture_output=True, text=True, timeout=600, cwd="/tmp")
    try:
        return json.loads(json.loads(completed.stdout)["text"])["examples"]
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError):
        return []


def problem(example: dict) -> str | None:
    """Why a labelled example breaks the diagram rules, or None when it passes."""
    try:
        if example["description"].count(".") < 3:
            return "too short"
        return diagram_problem(example["diagram"])
    except (KeyError, TypeError, AttributeError):
        return "bad shape"


def diagram_problem(diagram: dict) -> str | None:
    """Why a diagram breaks the diagram rules, or None when it passes."""
    try:
        boxes, edges = diagram["boxes"], diagram["edges"]
        if diagram["direction"] not in ("TD", "LR") or not all(isinstance(e, list) and len(e) == 3 for e in edges):
            return "bad shape"
    except (KeyError, TypeError):
        return "bad shape"
    if any(source not in boxes or target not in boxes for source, target, _ in edges):
        return "edge to unlisted box"
    if any(box not in {e[0] for e in edges} | {e[1] for e in edges} for box in boxes):
        return "unconnected box"
    for box in boxes:
        if box.endswith("?"):
            outcomes = sorted(label for source, _, label in edges if source == box)
            if not {"yes", "no"} >= set(outcomes) or not outcomes or len(outcomes) != len(set(outcomes)):
                return "decision outcomes"
            if [label for _, target, label in edges if target == box] != [""]:
                return "decision input"
    for source, _, label in edges:
        if label in ("yes", "no") and not source.endswith("?") or CONDITION_WORD.search(label):
            return "label"
    return None


def main() -> None:
    calls, mix_dir, output = int(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    rules, system_prompt, rng = diagram_rules(), load_whole_text_prompt(), random.Random(7)
    prompts = [INSTRUCTIONS.format(count=PER_CALL, topics=", ".join(rng.sample(TOPICS, PER_CALL)), rules=rules)
               for _ in range(calls)]
    # Each batch is saved as it arrives, so stopping early keeps the finished calls.
    output.mkdir(exist_ok=True)
    saved, total, rejected = output / "grok.jsonl", 0, {}
    with ThreadPoolExecutor(PARALLEL_CALLS) as pool, saved.open("a") as out:
        for done, future in enumerate(as_completed(pool.submit(ask_grok, p) for p in prompts), 1):
            for example in future.result():
                total += 1
                reason = problem(example)
                if reason:
                    rejected[reason] = rejected.get(reason, 0) + 1
                else:
                    out.write(json.dumps(example) + "\n")
            out.flush()
            print(f"call {done}/{calls}: {total} examples, rejected {rejected}", flush=True)
    kept = [json.loads(line) for line in saved.read_text().splitlines()]
    records = [json.dumps({"messages": [{"role": "system", "content": system_prompt},
                                        {"role": "user", "content": e["description"]},
                                        {"role": "assistant", "content": json.dumps(e["diagram"])}]}) + "\n"
               for e in kept]
    mixed = (mix_dir / "train.jsonl").read_text().splitlines(keepends=True) + records
    rng.shuffle(mixed)
    (output / "train.jsonl").write_text("".join(mixed))
    (output / "valid.jsonl").write_text((mix_dir / "valid.jsonl").read_text())
    print(f"kept {len(kept)} grok examples in total; train records: {len(mixed)}")


if __name__ == "__main__":
    main()
