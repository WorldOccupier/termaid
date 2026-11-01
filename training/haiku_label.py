"""Builds whole-description training examples: DeepSeek Flash writes descriptions, Haiku (xhigh) labels them.

Descriptions come from opencode-go so they don't use the Claude plan. Labels come from the claude CLI on the
Claude plan, so the run checks `/usage` as it goes: it pauses until the 5-hour window resets when the session
gets high, and stops when the weekly share gets high. Everything is appended as it arrives, so a rerun resumes.

Usage: haiku_label.py <kept examples wanted> <whole-text data dir to mix in> <output dir>
"""

import json
import random
import re
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from grok_label import TOPICS, problem
from whole_text import load_whole_text_prompt

WRITER_MODEL = "opencode-go/deepseek-v4.1-flash"
LABEL_MODEL, LABEL_EFFORT = "claude-haiku-5-5", "xhigh"
PER_WRITER_CALL = 5
LABEL_PARALLEL = 4
USAGE_CHECK_EVERY = 25
SESSION_PAUSE_AT, WEEK_STOP_AT = 75, 45
JSON_OBJECT = re.compile(r"\{.*\}", re.S)
LIMIT_WORDS = re.compile(r"usage limit|rate limit|limit reached|429", re.I)

WRITER_INSTRUCTIONS = """Write {count} descriptions of processes or systems, one per topic: {topics}.

Each description: 4-6 sentences of natural, varied English, like a person explaining it (lowercase,
run-on sentences and a typo are fine). Each one must include:
- 2 or 3 conditions phrased differently ("if ... otherwise", "only when", "only if ... not", "unless",
  "falling back to ... when", "on a miss", "else"). Make the box that CHECKS a condition differ from the
  boxes that act in each case.
- at least one step that loops back to an earlier box ("sends it back to", "retries").
- in about half: "X sits in front of Y", "Y is behind X", "Y has X in front of it" (sometimes mid-sentence),
  or "Y is replicated and uses round robin / least connections".
- in about a third: something that happens to everyone alongside something that only happens in one case
  ("every customer gets a receipt, and big orders also go to a manager").

Answer directly; do not use any tools or look at files.
Reply with only JSON: {{"descriptions": ["...", ...]}}"""


def write_descriptions(topics: list[str]) -> list[str]:
    prompt = WRITER_INSTRUCTIONS.format(count=len(topics), topics=", ".join(topics))
    try:
        completed = subprocess.run(["opencode", "run", "-m", WRITER_MODEL, prompt],
                                   capture_output=True, text=True, timeout=600, cwd="/tmp")
        return [d for d in json.loads(JSON_OBJECT.search(completed.stdout).group())["descriptions"]
                if isinstance(d, str)]
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError, subprocess.TimeoutExpired):
        return []


def label(system_prompt: str, description: str) -> tuple[dict | None, bool]:
    """The diagram Haiku draws (None if unusable), and whether the reply looked like a usage limit."""
    prompt = f"{system_prompt}\n\nNow convert this description. Reply with only the JSON.\n\n{description}"
    command = ["claude", "-p", prompt, "--model", LABEL_MODEL, "--effort", LABEL_EFFORT, "--tools", "",
               "--output-format", "json", "--no-session-persistence", "--strict-mcp-config"]
    try:
        completed = subprocess.run(command, capture_output=True, text=True, timeout=600, cwd="/tmp")
    except subprocess.TimeoutExpired:
        return None, False
    try:
        reply = json.loads(completed.stdout)
        if reply.get("is_error"):
            return None, bool(LIMIT_WORDS.search(str(reply.get("result"))))
        return json.loads(JSON_OBJECT.search(reply["result"]).group()), False
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError):
        return None, bool(LIMIT_WORDS.search(completed.stdout + completed.stderr))


def usage() -> tuple[int, int] | None:
    """(session %, week %) from `claude -p /usage`, or None if it can't be read."""
    try:
        text = subprocess.run(["claude", "-p", "/usage"], capture_output=True, text=True, timeout=120, cwd="/tmp").stdout
        session = re.search(r"Current session: (\d+)%", text)
        week = re.search(r"Current week \(all models\): (\d+)%", text)
        return int(session.group(1)), int(week.group(1))
    except (AttributeError, subprocess.TimeoutExpired):
        return None


def wait_for_room() -> None:
    """Returns once the plan has room; exits when the weekly share is too high."""
    while True:
        shares = usage()
        if shares is None:
            print("usage: unreadable, waiting 5 min", flush=True)
            time.sleep(300)
            continue
        session, week = shares
        print(f"usage: session {session}%, week {week}%", flush=True)
        if week >= WEEK_STOP_AT:
            sys.exit(f"stopping: weekly usage {week}% >= {WEEK_STOP_AT}%; rerun later to resume")
        if session < SESSION_PAUSE_AT:
            return
        print(f"session {session}% >= {SESSION_PAUSE_AT}%: pausing 15 min", flush=True)
        time.sleep(900)


def lines(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []


def ensure_descriptions(path: Path, wanted: int, rng: random.Random) -> list[str]:
    have = [d["description"] for d in lines(path)]
    calls = max(0, -(-(wanted - len(have)) // PER_WRITER_CALL))
    if calls:
        print(f"writing ~{calls * PER_WRITER_CALL} descriptions with {WRITER_MODEL}", flush=True)
        batches = [rng.sample(TOPICS, PER_WRITER_CALL) for _ in range(calls)]
        with ThreadPoolExecutor(8) as pool, path.open("a") as out:
            for done, written in enumerate(pool.map(write_descriptions, batches), 1):
                for d in written:
                    out.write(json.dumps({"description": d}) + "\n")
                out.flush()
                if done % 20 == 0:
                    print(f"  writer call {done}/{calls}", flush=True)
    return [d["description"] for d in lines(path)]


def main() -> None:
    wanted, mix_dir, output = int(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    output.mkdir(exist_ok=True)
    rng, system_prompt = random.Random(11), load_whole_text_prompt()
    descriptions = ensure_descriptions(output / "descriptions.jsonl", int(wanted * 1.8), rng)

    labelled_path = output / "labelled.jsonl"
    done = {r["description"] for r in lines(labelled_path)}
    kept = sum(1 for r in lines(labelled_path) if r["problem"] is None)
    todo = [d for d in descriptions if d not in done]
    print(f"{len(descriptions)} descriptions, {len(done)} labelled, {kept} kept, {len(todo)} to go", flush=True)

    with labelled_path.open("a") as out, ThreadPoolExecutor(LABEL_PARALLEL) as pool:
        for start in range(0, len(todo), USAGE_CHECK_EVERY):
            if kept >= wanted:
                break
            wait_for_room()
            chunk = todo[start:start + USAGE_CHECK_EVERY]
            results = list(pool.map(lambda d: label(system_prompt, d), chunk))
            if any(limited for _, limited in results):
                print("usage limit reply seen: pausing 30 min (unfinished ones retry on rerun)", flush=True)
                for d, (diagram, limited) in zip(chunk, results):
                    if not limited:
                        kept += record(out, d, diagram) is None
                time.sleep(1800)
                continue
            for d, (diagram, _) in zip(chunk, results):
                kept += record(out, d, diagram) is None
            reasons = {}
            for r in lines(labelled_path):
                reasons[r["problem"] or "kept"] = reasons.get(r["problem"] or "kept", 0) + 1
            print(f"labelled {start + len(chunk)}/{len(todo)}: {reasons}", flush=True)

    build_dataset(output, mix_dir, system_prompt, rng)


def record(out, description: str, diagram: dict | None) -> str | None:
    reason = "no json" if diagram is None else problem({"description": description, "diagram": diagram})
    out.write(json.dumps({"description": description, "diagram": diagram, "problem": reason}) + "\n")
    out.flush()
    return reason


def build_dataset(output: Path, mix_dir: Path, system_prompt: str, rng: random.Random) -> None:
    kept = [r for r in lines(output / "labelled.jsonl") if r["problem"] is None]
    records = [json.dumps({"messages": [{"role": "system", "content": system_prompt},
                                        {"role": "user", "content": r["description"]},
                                        {"role": "assistant", "content": json.dumps(r["diagram"])}]}) + "\n"
               for r in kept]
    mixed = (mix_dir / "train.jsonl").read_text().splitlines(keepends=True) + records
    rng.shuffle(mixed)
    (output / "train.jsonl").write_text("".join(mixed))
    (output / "valid.jsonl").write_text((mix_dir / "valid.jsonl").read_text())
    print(f"kept {len(kept)} haiku examples; train records: {len(mixed)}", flush=True)


if __name__ == "__main__":
    main()
