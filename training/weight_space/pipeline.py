"""Per-sentence pipeline (src/textToMermaid.ts `describe`) driven through wsprobe, keeping every step.

usage: python pipeline.py <model.gguf> <descriptions.txt> <out.jsonl>
Each output line: {"description", "steps": [{"sentence", "reply", "looped", "maxed", "ntok"}], "state" | "error"}.
Unlike the app's `eval`, this records the per-step replies and loop-detector trips.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent

SYSTEM = re.search(r"const PER_SENTENCE_PROMPT = `(.*?)`;", (ROOT / "src/textToMermaid.ts").read_text(), re.S).group(1)
SENTENCE_BREAK = re.compile(r"(?<=[.!?])\s+|\n+")
TOP_DOWN = re.compile(r"\b(top[\s-]+(to|down)[\s-]+bottom|vertical(ly)?|downwards?)\b", re.I)
LEFT_RIGHT = re.compile(r"\b(left[\s-]+to[\s-]+right|horizontal(ly)?|sideways)\b", re.I)


def split_sentences(text):
    return [s.strip() for s in SENTENCE_BREAK.split(text) if s and s.strip()]


def requested_direction(sentence):
    if len(sentence.strip().split()) > 8:
        return None
    if TOP_DOWN.search(sentence):
        return "TD"
    if LEFT_RIGHT.search(sentence):
        return "LR"
    return None


def nonempty(v):
    return isinstance(v, str) and v.strip() != ""


def normalize_reply(reply):
    reply = reply if isinstance(reply, dict) else {}
    boxes, edges = reply.get("boxes"), reply.get("edges")
    return {
        "direction": "TD" if reply.get("direction") == "TD" else "LR",
        "boxes": [b.strip() for b in boxes if nonempty(b)] if isinstance(boxes, list) else [],
        "edges": [[e[0].strip(), e[1].strip(), e[2].strip() if len(e) > 2 and isinstance(e[2], str) else ""]
                  for e in edges if isinstance(e, list) and len(e) >= 2 and nonempty(e[0]) and nonempty(e[1])]
        if isinstance(edges, list) else [],
    }


def format_update_request(state, sentence):
    return f"Diagram so far: {json.dumps(state, separators=(',', ':'), ensure_ascii=False)}\nNext sentence: {sentence}"


class Probe:
    def __init__(self, model, extra=()):
        self.p = subprocess.Popen([str(HERE / "wsprobe"), model, "-", "-", *extra],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE)

    def complete(self, system, user):
        self.p.stdin.write((system + "\x1f" + user + "\x1f\x1e").encode())
        self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())

    def close(self):
        self.p.stdin.close()
        self.p.wait()


def describe(probe, description):
    state = {"direction": "LR", "boxes": [], "edges": []}
    steps = []
    for sentence in split_sentences(description):
        d = requested_direction(sentence)
        if d:
            state = {**state, "direction": d}
            steps.append({"sentence": sentence, "direction_only": True})
            continue
        r = probe.complete(SYSTEM, format_update_request(state, sentence))
        steps.append({"sentence": sentence, "request": format_update_request(state, sentence), "reply": r["reply"],
                      "looped": r["looped"], "maxed": r["maxed"], "ntok": r["ntok"]})
        try:
            state = normalize_reply(json.loads(r["reply"]))
        except json.JSONDecodeError as e:
            return {"description": description, "steps": steps, "error": f"JSON: {e}"}
    return {"description": description, "steps": steps, "state": state}


def main():
    model, descs, out = sys.argv[1:4]
    probe = Probe(model)
    with open(out, "w") as f:
        for line in Path(descs).read_text().split("\n"):
            if line:
                f.write(json.dumps(describe(probe, line), ensure_ascii=False) + "\n")
                f.flush()
    probe.close()


if __name__ == "__main__":
    main()
