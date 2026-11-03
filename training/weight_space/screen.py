"""Cheap causal screen: teacher-forces the baseline replies of the contrast set and reports, at the decisive
rows, the mean log-prob of the token the baseline chose (orphan source vs connected source).

usage: python screen.py <contrast_dir> <model.gguf> [more.gguf ...]
An edit that targets the orphan behaviour should lower the orphan rows and leave connected rows alone.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
d = Path(sys.argv[1])
meta = json.loads((d / "meta.json").read_text())
for model in sys.argv[2:]:
    out = d / f"screen-{Path(model).stem}.jsonl"
    if not out.exists():
        subprocess.run([str(HERE / "wsprobe"), model, str(d / "req.bin"), str(out), "--force"], check=True)
    o, c, oa, ca = [], [], [], []
    for m, r in zip(meta, map(json.loads, open(out))):
        for y, k in zip(m["labels"], r["rows"]):
            (o if y else c).append(r["logprobs"][k])
            (oa if y else ca).append(r["argmax"][k])
    print(f"{Path(model).stem:40s} orphan lp {np.mean(o):7.3f} argmax {np.mean(oa):.2f} | connected lp {np.mean(c):7.3f} argmax {np.mean(ca):.2f}")
