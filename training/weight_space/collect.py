"""Builds the contrast set for the "orphan source" failure and dumps activations at the decisive tokens.

usage: python collect.py <model.gguf> <out_dir> <pipeline.jsonl|gen.jsonl:req.bin> ...
For every step that adds edges to a non-empty diagram, each new edge's source name is the decision:
  orphan    = the source is a box new in this step that nothing in the reply leads into
  connected = the source is a box already in the diagram
The model's own reply is teacher-forced and the residual (l_out) and MLP write (ffn) at all layers is kept
only for the row predicting the first token of that source name.
"""
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def steps_from(spec):
    if spec.endswith(".jsonl") and ":" not in spec:
        for row in map(json.loads, open(spec)):
            for s in row["steps"]:
                if "request" in s:
                    yield s["request"], s["reply"]
    else:
        gen, req = spec.split(":")
        reqs = Path(req).read_bytes().decode().split("\x1e")
        for g, r in zip(map(json.loads, open(gen)), reqs):
            yield r.split("\x1f")[1], g["reply"]


def label(request, reply):
    prev = json.loads(request.split("Diagram so far: ", 1)[1].split("\nNext sentence:", 1)[0])
    try:
        st = json.loads(reply)
    except json.JSONDecodeError:
        return []
    pe, edges = prev["edges"], st["edges"]
    if not pe or [e[:2] for e in edges[: len(pe)]] != [e[:2] for e in pe]:
        return []
    known = set(prev["boxes"]) | {x for e in pe for x in e[:2]}
    reached = {e[1] for e in edges}
    out, pos = [], 0
    # byte offset of each edge's source name in the reply text
    for k, e in enumerate(edges):
        pos = reply.index("[" + json.dumps(e[0], ensure_ascii=False), pos + 1 if k else reply.index('"edges"'))
        if k < len(pe):
            continue
        src = e[0]
        if src in known:
            out.append((pos + 2, 0))
        elif src not in reached:
            out.append((pos + 2, 1))
    return out


def main():
    model, out_dir, *specs = sys.argv[1:]
    out = Path(out_dir)
    out.mkdir(exist_ok=True)
    system = __import__("pipeline").SYSTEM
    recs, meta = [], []
    for spec in specs:
        for request, reply in steps_from(spec):
            lab = label(request, reply)
            if not lab:
                continue
            recs.append(system + "\x1f" + request + "\x1f" + reply + "\x1f" + ",".join(str(o) for o, _ in lab) + "\x1e")
            meta.append({"src": spec, "labels": [y for _, y in lab], "offsets": [o for o, _ in lab],
                         "names": [reply[o:reply.index('"', o)] for o, _ in lab]})
    (out / "req.bin").write_text("".join(recs))
    (out / "meta.json").write_text(json.dumps(meta))
    n1 = sum(sum(m["labels"]) for m in meta)
    n0 = sum(len(m["labels"]) for m in meta) - n1
    print(f"{len(meta)} steps, {n1} orphan-source decisions, {n0} connected-source decisions", flush=True)
    subprocess.run([str(HERE / "wsprobe"), model, str(out / "req.bin"), str(out / "force.jsonl"), "--force",
                    "--dump", str(out / "acts"), "--names", "l_out,ffn"], check=True)


if __name__ == "__main__":
    (Path(sys.argv[2]) / "acts").mkdir(parents=True, exist_ok=True)
    main()
