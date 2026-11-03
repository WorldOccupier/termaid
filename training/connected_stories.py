"""Long multi-step stories where every sentence continues the flow, written and labelled by Claude.

The template stories (story.py) often start a follow-up with a brand-new actor, so their gold diagrams
have boxes nothing leads into, and the model learned to leave steps beside the flow. Here Claude writes
realistic descriptions in which every later sentence continues from a box already drawn, plus the
diagram after each sentence. Holdout topics are excluded (see grok_label.TOPICS).

Usage: connected_stories.py <calls> <stories per call> <model> <output dir>
Appends the stories that parse to <output dir>/stories.jsonl; build_data.py turns them into steps.
"""

import json
import random
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from claude_cli import ask_json
from generate_data import load_system_prompt, to_chat_record
from grok_label import TOPICS
from story import split_sentences

PARALLEL_CALLS = 5
EMPTY_DIAGRAM = {"direction": "LR", "boxes": [], "edges": []}

INSTRUCTIONS = """Write {count} training stories for a small model that builds a flowchart one sentence at a time.
Topics, one each: {topics}.

Each story: 5-8 sentences of natural, varied English, like a person explaining a process to a colleague
(lowercase, run-on sentences and the odd typo are fine). Each sentence is one step, so no sentence may
contain ".", "!" or "?" before its end.
- The first sentence starts the process. Every later sentence continues from a box already in the diagram
  (it names something already drawn as the one acting or being acted on), so the finished flowchart has
  exactly one starting box that nothing leads into.
- Include 2 or 3 conditions phrased differently ("if ... otherwise", "only when", "unless", "falling back
  to ... when", "on a miss", "else"). The box that checks a condition differs from the boxes that act in
  each case.
- At least one step loops back to an earlier box ("sends it back to", "retries").
- In about half: "X sits in front of Y" / "there is an X before Y", or "Y is replicated and uses round robin".

After each sentence give the full diagram so far, following the rules a model is given below. On top of
those rules, every diagram must satisfy:
- every box appears in at least one edge, and only the first box has nothing leading into it;
- every decision box has exactly one incoming edge, with an empty label, from the box that checks it;
- a decision's outcomes are at most one "yes" and at most one "no", never both to the same box;
- a different check gets its own decision box, even if the question sounds similar.

Rules the model is given:
<rules>
{rules}
</rules>

Answer directly from these instructions; do not use any tools or look at files.
Reply with only JSON: {{"stories": [{{"sentences": ["...", ...], "diagrams": [{{"direction": "LR", "boxes": [...], "edges": [[from, to, label], ...]}}, ...]}}, ...]}}
with exactly one diagram per sentence."""


def build_prompts(rng: random.Random, calls: int, per_call: int, rules: str,
                  topic_list: list[str] = TOPICS, instructions: str = INSTRUCTIONS) -> list[str]:
    """Cycles through the shuffled topics so none repeats until every one has been used."""
    order = rng.sample(topic_list, len(topic_list))
    topics = [order[i % len(order)] for i in range(calls * per_call)]
    return [instructions.format(count=per_call, topics=", ".join(topics[i:i + per_call]), rules=rules)
            for i in range(0, len(topics), per_call)]


def story_problem(story: dict) -> str | None:
    """Why a reply story can't be turned into steps, or None when it can."""
    try:
        sentences, diagrams = story["sentences"], story["diagrams"]
    except (KeyError, TypeError):
        return "bad shape"
    if not sentences or len(sentences) != len(diagrams):
        return "sentence and diagram counts differ"
    if any(len(split_sentences(sentence)) != 1 for sentence in sentences):
        return "a sentence splits in two"
    return None


def story_records(story: dict, system_prompt: str) -> list[dict]:
    befores = [EMPTY_DIAGRAM, *story["diagrams"][:-1]]
    return [to_chat_record(system_prompt, before, sentence, after)
            for before, sentence, after in zip(befores, story["sentences"], story["diagrams"])]


def collect_stories(prompts: list[str], model: str, raw_output: Path) -> list[dict]:
    """Saves each reply as it arrives, so stopping early keeps the finished calls."""
    stories, rejected = [], {}
    with ThreadPoolExecutor(PARALLEL_CALLS) as pool, raw_output.open("a") as raw:
        futures = [pool.submit(ask_json, prompt, model) for prompt in prompts]
        for done, future in enumerate(as_completed(futures), 1):
            reply = future.result() or {}
            for story in reply.get("stories", []):
                reason = story_problem(story)
                if reason:
                    rejected[reason] = rejected.get(reason, 0) + 1
                    continue
                stories.append(story)
                raw.write(json.dumps(story) + "\n")
            raw.flush()
            print(f"call {done}/{len(prompts)}: {len(stories)} stories, rejected {rejected}", flush=True)
    return stories


def main() -> None:
    calls, per_call, model, output = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], Path(sys.argv[4])
    system_prompt = load_system_prompt()
    output.mkdir(exist_ok=True)
    prompts = build_prompts(random.Random(11), calls, per_call, system_prompt)
    stories = collect_stories(prompts, model, output / "stories.jsonl")
    print(f"saved {len(stories)} stories to {output / 'stories.jsonl'}")


if __name__ == "__main__":
    main()
