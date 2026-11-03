"""Builds a training set: data-v9 without the steps that break the checks, plus Claude's stories.

A v9 step is dropped when it introduces a problem (measure_problems.ts: findProblems and
findStepProblems). A Claude story is dropped whole when any of its steps does, since later steps build
on the broken diagram. Whole stories go to one split, so validation never sees steps of a training story.

Usage: build_data.py <v9 dir> <output dir> <stories.jsonl>...
data-v10 = data-sonnet stories; data-v11 = data-sonnet + data-targeted stories.
"""

import json
import random
import subprocess
import sys
import tempfile
from pathlib import Path

from connected_stories import story_records
from generate_data import load_system_prompt

TRAINING_DIR = Path(__file__).parent
VALID_STORY_RATE = 0.1
SEED = 13


def flagged_lines(path: Path) -> set[int]:
    """1-based line numbers of the steps in `path` that introduce a findProblems problem."""
    with tempfile.NamedTemporaryFile(suffix=".jsonl") as listing:
        subprocess.run(["node", str(TRAINING_DIR / "measure_problems.ts"), str(path.resolve()), "--list", listing.name],
                       cwd=TRAINING_DIR.parent, check=True, capture_output=True)
        return {json.loads(line)["line"] for line in Path(listing.name).read_text().splitlines() if line}


def clean_lines(path: Path) -> list[str]:
    flagged = flagged_lines(path)
    lines = path.read_text().splitlines()
    print(f"{path}: dropped {len(flagged)} of {len(lines)} steps")
    return [line for number, line in enumerate(lines, 1) if number not in flagged]


def clean_stories(stories_path: Path, system_prompt: str) -> list[list[str]]:
    """Each story's steps as JSON lines, without stories that have a flagged step."""
    stories = [json.loads(line) for line in stories_path.read_text().splitlines() if line]
    steps = [[json.dumps(record) for record in story_records(story, system_prompt)] for story in stories]
    story_of_line = [index for index, story_steps in enumerate(steps) for _ in story_steps]
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl") as all_steps:
        all_steps.write("".join(line + "\n" for story_steps in steps for line in story_steps))
        all_steps.flush()
        broken = {story_of_line[number - 1] for number in flagged_lines(Path(all_steps.name))}
    print(f"{stories_path}: dropped {len(broken)} of {len(stories)} stories")
    return [story_steps for index, story_steps in enumerate(steps) if index not in broken]


def write_lines(path: Path, lines: list[str]) -> None:
    path.write_text("".join(line + "\n" for line in lines))


def main() -> None:
    v9_dir, output, story_paths = Path(sys.argv[1]), Path(sys.argv[2]), map(Path, sys.argv[3:])
    rng = random.Random(SEED)
    system_prompt = load_system_prompt()
    stories = [story for path in story_paths for story in clean_stories(path, system_prompt)]
    rng.shuffle(stories)
    valid_count = round(len(stories) * VALID_STORY_RATE)
    train = clean_lines(v9_dir / "train.jsonl") + [line for story in stories[valid_count:] for line in story]
    valid = clean_lines(v9_dir / "valid.jsonl") + [line for story in stories[:valid_count] for line in story]
    rng.shuffle(train)
    output.mkdir(exist_ok=True)
    write_lines(output / "train.jsonl", train)
    write_lines(output / "valid.jsonl", valid)
    print(f"wrote {len(train)} train / {len(valid)} valid steps to {output}")


if __name__ == "__main__":
    main()
