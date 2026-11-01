"""Generate synthetic description -> flowchart JSON pairs for fine-tuning.

Every example is built from templates, so the target diagram is correct by construction.
Each record is one step of a story from story.py: (diagram so far, next sentence) -> new diagram.
Output is mlx-lm chat format: <dir>/train.jsonl and <dir>/valid.jsonl.
"""

import json
import os
import random
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

from domains import Domain


TRAINING_DIR = Path(__file__).parent
REPO_DIR = TRAINING_DIR.parent
DATA_DIR = TRAINING_DIR / "data"
BASE_MODEL = os.environ.get("TERMAID_BASE_MODEL", "Qwen/Qwen2.5-1.5B-Instruct")
TRAIN_COUNT = 4000
VALID_COUNT = 250
SEED = 7
# --reword sends each story to Claude through the `claude` CLI, this many at once.
REWORD_WORKERS = 8
STORIES_PER_BATCH = 48
# Stories per Claude call: each call has a fixed overhead, so batching keeps usage down.
STORIES_PER_CALL = 6

# Conditions that open a sentence: "on a miss, ..."
EVENTS = [("a miss", "Miss?"), ("failure", "Failed?"), ("a timeout", "Timeout?"), ("an error", "Error?"),
          ("success", "Succeeded?"), ("a hit", "Hit?")]

# No periods: each sentence is a separate model step at runtime, so one generated step must stay
# one sentence. Multi-sentence descriptions come from story.py instead.
CONNECTORS = [", and then ", ", then ", "; then ", " and ", ", after that ", ", next "]


@dataclass
class Example:
    text: str
    boxes: list[str] = field(default_factory=list)
    edges: list[list[str]] = field(default_factory=list)

    def box(self, name: str) -> str:
        if name not in self.boxes:
            self.boxes.append(name)
        return name

    def edge(self, source: str, target: str, label: str) -> None:
        self.edges.append([self.box(source), self.box(target), label])


def capitalize(sentence: str) -> str:
    return sentence[0].upper() + sentence[1:]


def plain_step(rng, domain: Domain, example, source, target):
    label, phrase = rng.choice(domain.verbs)
    example.edge(source[0], target[0], label)
    return f"{source[1]} {phrase} {target[1]}"


# Only these sentence shapes route *away* from a box when its condition is true ("falling back to
# local disk when S3 is down"), so only they may name the condition after the target box.
# Elsewhere it teaches nonsense like "updates the cache only if the cache misses" -> yes -> Cache.
KINDS_AVOIDING_TARGET = {"fallback", "unless"}


def pick_condition(rng, domain: Domain, kind, target):
    """For fallback/unless, half the time the condition names the target: "S3 is down" -> "S3 down?"."""
    if kind not in KINDS_AVOIDING_TARGET or rng.random() < 0.5:
        question, wordings = rng.choice(domain.conditions)
        return question, rng.choice(wordings)
    question, text = rng.choice(domain.thing_conditions)
    return question.format(target[0]), text.format(target[1])


def conditional_step(rng, domain: Domain, example, source, target, other):
    """One sentence with a condition; returns its text and wires the decision box."""
    label, phrase = rng.choice(domain.verbs)
    other_label, other_phrase = rng.choice(domain.verbs)
    kind = rng.choice(["only_if", "if_else", "when_else", "unless", "fallback", "leading_if", "on_event", "event_led"])
    question, condition = pick_condition(rng, domain, kind, target)
    if kind == "event_led":
        event, question = rng.choice(EVENTS)
        example.edge(source[0], question, "")
        example.edge(question, target[0], "yes")
        return f"on {event} {source[1]} {phrase} {target[1]}"
    example.edge(source[0], question, "")
    if kind == "only_if":
        example.edge(question, target[0], "yes")
        return f"{source[1]} {phrase} {target[1]} only if {condition}"
    if kind == "if_else":
        example.edge(question, target[0], "yes")
        example.edge(question, other[0], "no")
        return f"{source[1]} {phrase} {target[1]} if {condition}, {rng.choice(['otherwise', 'else'])} it {other_phrase} {other[1]}"
    if kind == "when_else":
        example.edge(question, target[0], "yes")
        example.edge(question, other[0], "no")
        return f"when {condition} {source[1]} {phrase} {target[1]}, {rng.choice(['otherwise', 'else'])} it {other_phrase} {other[1]}"
    if kind == "unless":
        example.edge(question, target[0], "no")
        return f"{source[1]} {phrase} {target[1]} unless {condition}"
    if kind == "fallback":
        example.edge(question, target[0], "no")
        example.edge(question, other[0], "yes")
        return f"{source[1]} {phrase} {target[1]}, falling back to {other[1]} when {condition}"
    if kind == "leading_if":
        example.edge(question, target[0], "yes")
        return f"if {condition}, {source[1]} {phrase} {target[1]}"
    example.edge(question, target[0], "yes")
    example.edge(question, other[0], "no")
    return f"{source[1]} {phrase} {target[1]} only if {condition} else {rng.choice(['uses', 'goes to', 'falls back to'])} {other[1]}"


def make_procedure_example(rng: random.Random, domain: Domain) -> Example:
    """'compile the code, lint the files, and if it passes package the release, otherwise roll back'"""
    example = Example(text="")
    steps = rng.sample(domain.steps, 4)
    example.edge(steps[0][0], steps[1][0], "then")
    question, wordings = rng.choice(domain.step_outcomes)
    example.edge(steps[1][0], question, "")
    example.edge(question, steps[2][0], "yes")
    text = f"{steps[0][1]}, {steps[1][1]}, and if {rng.choice(wordings)} {steps[2][1]}"
    if rng.random() < 0.7:
        example.edge(question, steps[3][0], "no")
        text += f", {rng.choice(['otherwise', 'else'])} {steps[3][1]}"
    example.text = capitalize(text) + "." if rng.random() < 0.5 else text
    return example


def make_example(rng: random.Random, domain: Domain) -> Example:
    if rng.random() < 0.15:
        return make_procedure_example(rng, domain)
    example = Example(text="")
    things = rng.sample(domain.things, 5)
    # Some sentences open with the condition, so it controls the very first action.
    if rng.random() < 0.25:
        example.text = conditional_step(rng, domain, example, things[0], things[1], things[2])
        return example
    clauses = [plain_step(rng, domain, example, things[0], things[1])]
    # About a third of examples have no condition, so the model doesn't add diamonds everywhere.
    if rng.random() < 0.35:
        clauses.append(plain_step(rng, domain, example, things[1], things[2]))
        if rng.random() < 0.5:
            clauses.append(plain_step(rng, domain, example, things[2], things[3]))
    else:
        clauses.append(conditional_step(rng, domain, example, things[1], things[2], things[3]))
        if rng.random() < 0.25:
            clauses.append(plain_step(rng, domain, example, things[2], things[4]))
    text = clauses[0]
    for subject, clause in zip(things[1:], clauses[1:]):
        # Dictation often chains with "..., which ..." instead of repeating the subject.
        if clause.startswith(subject[1]) and rng.random() < 0.35:
            text += ", which" + clause[len(subject[1]):]
        else:
            text += rng.choice(CONNECTORS) + clause
    example.text = capitalize(text) + "." if rng.random() < 0.5 else text
    return example


def to_chat_record(system_prompt: str, before: dict, sentence: str, after: dict) -> dict:
    from story import format_update_request
    return {"messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": format_update_request(before, sentence)},
        {"role": "assistant", "content": json.dumps(after)},
    ]}


def make_records(rng: random.Random, system_prompt: str, count: int, reword: bool) -> list[dict]:
    """Whole stories go to one split, so validation never sees steps of a training story.

    Each story gets its own seeded generator, so rewording batches can run in parallel and the
    output stays the same for the same seed.
    """
    from rewording import reword_stories
    from story import add_story_typos, make_story, split_sentences
    records = []
    with ThreadPoolExecutor(REWORD_WORKERS) as pool:
        while len(records) < count:
            rngs = [random.Random(rng.random()) for _ in range(STORIES_PER_BATCH)]
            stories = [make_story(r) for r in rngs]
            sentences = [[sentence for _, sentence, _ in steps] for steps, _ in stories]
            if reword:
                calls = [(random.Random(rng.random()), stories[i:i + STORIES_PER_CALL])
                         for i in range(0, len(stories), STORIES_PER_CALL)]
                rewritten = pool.map(lambda call: reword_stories(*call, split_sentences), calls)
                sentences = [story for call in rewritten for story in call]
                print(f"  {min(len(records), count)}/{count}", file=sys.stderr)
            for r, (steps, _), story_sentences in zip(rngs, stories, sentences):
                records += [to_chat_record(system_prompt, *step) for step in add_story_typos(r, steps, story_sentences)]
    return records[:count]


def load_system_prompt() -> str:
    script = 'import("./src/textToMermaid.ts").then((m) => process.stdout.write(m.PER_SENTENCE_PROMPT))'
    return subprocess.run(["node", "-e", script], cwd=REPO_DIR, check=True, capture_output=True, text=True).stdout


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.write_text("".join(json.dumps(record) + "\n" for record in records))


def main() -> None:
    rng = random.Random(SEED)
    system_prompt = load_system_prompt()
    reword = "--reword" in sys.argv
    names = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
    output_dir = TRAINING_DIR / names[0] if names else DATA_DIR
    output_dir.mkdir(exist_ok=True)
    write_jsonl(output_dir / "train.jsonl", make_records(rng, system_prompt, TRAIN_COUNT, reword))
    write_jsonl(output_dir / "valid.jsonl", make_records(rng, system_prompt, VALID_COUNT, reword))
    print(f"wrote {TRAIN_COUNT} train / {VALID_COUNT} valid examples to {output_dir}")


if __name__ == "__main__":
    main()
