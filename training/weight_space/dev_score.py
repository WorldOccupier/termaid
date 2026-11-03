"""Scores wsprobe gen output on the data-v9 validation steps against the gold replies.

usage: python dev_score.py <gen.jsonl> [more.jsonl ...]   (rows aligned with dev/valid-req.bin)
Per step: parsed?, looped?, exact match with gold, edge F1, findProblems-style decision checks.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GOLD = [json.loads(json.loads(l)["messages"][2]["content"]) for l in open(HERE.parent / "data-v9/valid.jsonl")]


def norm_edges(state):
    return {(a.strip().lower(), b.strip().lower(), (l or "").strip().lower()) for a, b, *rest in state.get("edges", []) for l in [rest[0] if rest else ""]}


def decision_problems(state):
    edges = state.get("edges", [])
    boxes = set(state.get("boxes", [])) | {e[0] for e in edges} | {e[1] for e in edges}
    bad = 0
    for d in [b for b in boxes if b.endswith("?")]:
        out = [e for e in edges if e[0] == d]
        labels = [e[2] for e in out]
        if not out or any(l not in ("yes", "no") for l in labels) or len(set(labels)) != len(labels):
            bad += 1
        elif len(out) == 2 and out[0][1] == out[1][1]:
            bad += 1
        elif sum(e[1] == d for e in edges) != 1:
            bad += 1
    return bad


def extra_entries(state):
    edges = state.get("edges", [])
    reached = {e[1] for e in edges}
    entries = list(dict.fromkeys(e[0] for e in edges if e[0] not in reached))
    return max(0, len(entries) - 1)


def score(path):
    rows = [json.loads(l) for l in open(path)]
    s = dict(n=len(rows), parsed=0, looped=0, exact=0, edge_f1=0.0, decision_problems=0, missing_no=0, extra_entry=0, gold_extra_entry=0)
    per = []
    for r, gold in zip(rows, GOLD):
        rec = {"i": r["i"], "looped": r["looped"], "ok": False}
        s["looped"] += r["looped"]
        try:
            st = json.loads(r["reply"])
        except json.JSONDecodeError:
            per.append(rec)
            continue
        s["parsed"] += 1
        ge, pe = norm_edges(gold), norm_edges(st)
        tp = len(ge & pe)
        f1 = 2 * tp / (len(ge) + len(pe)) if ge or pe else 1.0
        s["edge_f1"] += f1
        ex = ge == pe and {b.lower() for b in gold["boxes"]} == {b.lower() for b in st.get("boxes", [])}
        s["exact"] += ex
        dp = decision_problems(st)
        s["decision_problems"] += dp
        # gold has a "no" branch for a decision the model left without one
        gno = {e[0] for e in gold["edges"] if e[2] == "no"}
        pno = {e[0] for e in st.get("edges", []) if e[2] == "no"}
        s["missing_no"] += len(gno) > len(pno)
        ee, gee = extra_entries(st), extra_entries(gold)
        s["extra_entry"] += ee > gee
        s["gold_extra_entry"] += gee > 0
        rec.update(extra_entry=ee > gee)
        rec.update(ok=True, exact=ex, f1=f1, dp=dp)
        per.append(rec)
    s["edge_f1"] = round(s["edge_f1"] / max(1, s["n"]), 4)
    return s, per


if __name__ == "__main__":
    for p in sys.argv[1:]:
        s, _ = score(p)
        print(Path(p).name, json.dumps(s))
