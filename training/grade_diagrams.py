"""Grades finished diagrams against their descriptions with Claude (CLI), because findProblems only sees
the diagram's shape: a diagram can pass it and still send "yes" to the wrong box.

Usage: grade_diagrams.py <descriptions.txt> <eval results.jsonl> <grades.jsonl> [model]
Writes one line per description: {"description", "errors": [{"kind", "severity", "detail"}]}.
Prints each diagram's major/minor counts and the totals by kind.
"""

import json
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from claude_cli import ask_json
from generate_data import load_system_prompt

PARALLEL_CALLS = 5
SYSTEM_PROMPT = "You grade flowcharts against the text they were drawn from. Reply with only the requested JSON."

INSTRUCTIONS = """A small model drew a flowchart from a description, one sentence at a time, following these rules:
<rules>
{rules}
</rules>

Description:
<description>
{description}
</description>

Finished diagram:
<diagram>
{diagram}
</diagram>

List every way the diagram misrepresents the process the description gives. Kinds:
- missing_step: a step, box or outcome path the text describes is absent, including an "otherwise" / "the
  rest" path, or a flow that dead-ends where the text continues it
- wrong_checker: a decision box is checked by the wrong box (the edge into it comes from a box that doesn't
  make that decision)
- wrong_target: an edge goes to the wrong box, including yes and no swapped and an outcome that points back
  at a box when the text says something else happens
- lost_loop: a retry, "again" or send-back loop the text describes is missing
- made_up: an edge or box the text doesn't describe that changes the flow

Severity: "major" when it changes what the process does or leaves a described path out; "minor" for a
harmless extra box, an edge drawn in the opposite direction for a passive relation ("reads from"), a
decision phrased with the opposite polarity whose yes/no still match, or a missing detail that doesn't
change the flow (a time limit, a count, a label). Box names and label wording don't matter. Don't report
the same mistake twice.

Answer directly; do not use any tools. Reply with only JSON:
{{"errors": [{{"kind": "<one of the kinds>", "severity": "major" | "minor", "detail": "<one sentence>"}}]}}
with an empty list when the diagram is right."""


def grade(rules: str, description: str, state: dict | None, model: str) -> list[dict]:
    if state is None:
        return [{"kind": "missing_step", "severity": "major", "detail": "the model produced no diagram"}]
    prompt = INSTRUCTIONS.format(rules=rules, description=description, diagram=json.dumps(state))
    for _ in range(2):
        reply = ask_json(prompt, model, SYSTEM_PROMPT)
        if isinstance(reply, dict) and isinstance(reply.get("errors"), list):
            return reply["errors"]
    raise RuntimeError(f"no grade for: {description[:60]}")


def print_summary(grades: list[dict]) -> None:
    kinds = Counter()
    for number, row in enumerate(grades, 1):
        severities = Counter(error["severity"] for error in row["errors"])
        kinds.update(error["kind"] for error in row["errors"] if error["severity"] == "major")
        print(f"#{number}: {severities['major']} major, {severities['minor']} minor")
    majors = [sum(e["severity"] == "major" for e in row["errors"]) for row in grades]
    print(f"correct (0 major): {majors.count(0)}/{len(grades)}, major errors: {sum(majors)}, by kind: {dict(kinds)}")


def main() -> None:
    descriptions_path, results_path, grades_path = map(Path, sys.argv[1:4])
    model = sys.argv[4] if len(sys.argv) > 4 else "sonnet"
    descriptions = [line for line in descriptions_path.read_text().splitlines() if line.strip()]
    states = [json.loads(line).get("state") for line in results_path.read_text().splitlines() if line.strip()]
    if len(states) != len(descriptions):
        sys.exit(f"{len(descriptions)} descriptions but {len(states)} results")
    rules = load_system_prompt()
    with ThreadPoolExecutor(PARALLEL_CALLS) as pool:
        errors = list(pool.map(lambda pair: grade(rules, *pair, model), zip(descriptions, states)))
    grades = [{"description": d, "errors": e} for d, e in zip(descriptions, errors)]
    grades_path.write_text("".join(json.dumps(row) + "\n" for row in grades))
    print_summary(grades)


if __name__ == "__main__":
    main()
