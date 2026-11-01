"""Change-only replies: the model says what a sentence changes instead of rewriting the diagram.

Rewriting the whole diagram every sentence lets the model drop or garble earlier edges, and the
reply grows with the diagram. Here the reply is {"direction", "rename", "remove", "add"} and code
merges it, so earlier parts can't be damaged.

Usage: changes.py <full-diagram data dir> <output dir>   (converts mlx-lm chat data)
"""

import json
import re
import sys
from pathlib import Path

STRATEGY_SUFFIX = re.compile(r" \([^)]*\)$")

CHANGES_PROMPT = """You build a flowchart one sentence at a time.
You get the diagram so far as JSON and the next sentence of the description. Reply with only what
the sentence changes, as JSON: {"direction": "TD" | "LR", "rename": [["<old box>", "<new box>"], ...],
"remove": [["<from box>", "<to box>", "<label>"], ...], "add": [["<from box>", "<to box>", "<label>"], ...]}.
Renames apply first, then removals, then additions. Reuse existing box names exactly when the
sentence mentions the same thing. Add new things, systems or steps as boxes (short names, 1-3
words) by adding edges to them.
Labels are short verb phrases (1-4 words) from the text saying how the boxes relate, e.g.
"sends credentials", "reads from". Labels never contain conditions ("if", "when", "otherwise").
Conditions become decision boxes instead: a short question ending in "?", e.g. "Cache miss?".
Connect the box that checks the condition to the decision box with an empty label, then draw
one edge per outcome from the decision box, labeled "yes" or "no", to the box that happens in
that case. A component placed "in front of" a box takes over the edges into that box: remove
those edges, add them to the component instead, and add an edge "routes to" from it. A box that
is multiple or replicated is renamed with the strategy in its name, e.g. "Database" to
"Database (round robin)". Only include steps the text describes.

Example:
Diagram so far: {"direction":"LR","boxes":[],"edges":[]}
Next sentence: The user logs in to the web app, which asks the API to check the database.
Reply: {"direction": "LR", "rename": [], "remove": [], "add": [["User", "Web App", "logs in"],
  ["Web App", "API", "asks to check"], ["API", "Database", "checks"]]}

Example:
Diagram so far: {"direction":"LR","boxes":["User","Web App","API","Database"],"edges":[["User","Web App","logs in"],["Web App","API","asks to check"],["API","Database","checks"]]}
Next sentence: If the token has expired the API calls the auth server, otherwise it reuses the session.
Reply: {"direction": "LR", "rename": [], "remove": [], "add": [["API", "Token expired?", ""],
  ["Token expired?", "Auth Server", "yes"], ["Token expired?", "Session", "no"]]}

Example:
Diagram so far: {"direction":"LR","boxes":["User","Web App","API"],"edges":[["User","Web App","logs in"],["Web App","API","calls"]]}
Next sentence: There is a gateway in front of the API, and the API is replicated with round robin.
Reply: {"direction": "LR", "rename": [["API", "API (round robin)"]], "remove": [["Web App", "API (round robin)", "calls"]],
  "add": [["Web App", "Gateway", "calls"], ["Gateway", "API (round robin)", "routes to"]]}"""


def apply_changes(state: dict, changes: dict) -> dict:
    """Raises KeyError/TypeError/ValueError on a malformed reply, like json.loads does for bad JSON."""
    renames = dict(changes["rename"])
    edges = [[renames.get(source, source), renames.get(target, target), label] for source, target, label in state["edges"]]
    removed = [list(edge) for edge in changes["remove"]]
    edges = [edge for edge in edges if edge not in removed]
    for edge in changes["add"]:
        if not (isinstance(edge, list) and len(edge) == 3):
            raise ValueError("edge is not [from, to, label]")
        if edge not in edges:
            edges.append(edge)
    boxes = list(dict.fromkeys(box for edge in edges for box in edge[:2]))
    return {"direction": changes.get("direction", state["direction"]), "boxes": boxes, "edges": edges}


def diff(before: dict, after: dict) -> dict:
    gone = [box for box in before["boxes"] if box not in after["boxes"]]
    renames = [[box, new] for box in gone for new in after["boxes"]
               if new not in before["boxes"] and STRATEGY_SUFFIX.sub("", new) == box]
    renamed = apply_changes(before, {"rename": renames, "remove": [], "add": []})
    changes = {"direction": after["direction"], "rename": renames,
               "remove": [e for e in renamed["edges"] if e not in after["edges"]],
               "add": [e for e in after["edges"] if e not in renamed["edges"]]}
    if sorted(map(tuple, apply_changes(before, changes)["edges"])) != sorted(map(tuple, after["edges"])):
        raise ValueError("changes don't rebuild the target diagram")
    return changes


def convert_record(record: dict) -> dict:
    _, request, reply = record["messages"]
    before = json.loads(request["content"].split("\n")[0].removeprefix("Diagram so far: "))
    changes = diff(before, json.loads(reply["content"]))
    return {"messages": [{"role": "system", "content": CHANGES_PROMPT}, request,
                         {"role": "assistant", "content": json.dumps(changes)}]}


def main() -> None:
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    output.mkdir(exist_ok=True)
    for name in ["train.jsonl", "valid.jsonl"]:
        records, skipped = [], 0
        for line in (source / name).read_text().splitlines():
            try:
                records.append(convert_record(json.loads(line)))
            except ValueError:
                skipped += 1
        (output / name).write_text("".join(json.dumps(r) + "\n" for r in records))
        print(f"{name}: {len(records)} converted, {skipped} skipped")


if __name__ == "__main__":
    main()
