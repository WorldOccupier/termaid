"""Writes per-layer directions for edit_gguf.py from the contrast activations (orphan minus connected means).

usage: python dirs.py <contrast_dir> <out.npz> <kind> <layers>
  kind = residN  -> the residual (l_out) direction at layer N, the same for every listed layer
  kind = resid   -> each listed layer's own residual (l_out) direction
  kind = ffn     -> each listed layer's own MLP-write difference (what that MLP writes more for orphans)
  kind = attn    -> each listed layer's own attention/conv-write difference (l_out[L] - l_out[L-1] - ffn[L])
"""
import sys
from pathlib import Path

import numpy as np

import analyze

d, out, kind, layers = sys.argv[1:5]
X, y, _, keys = analyze.load(Path(d))
nL = len(keys) // 2
R, F = X[:, :nL], X[:, nL:]
md = lambda A: A[y == 1].mean(0) - A[y == 0].mean(0)
dirs = {}
for L in map(int, layers.split(",")):
    v = md(R[:, L]) if kind == "resid" else md(R[:, int(kind[5:])]) if kind.startswith("resid") else md(F[:, L]) if kind == "ffn" else md(R[:, L] - R[:, L - 1]) - md(F[:, L])
    dirs[f"L{L}"] = v / np.linalg.norm(v)
np.savez(out, **dirs)
print(out, {k: round(float(np.linalg.norm(md(R[:, int(k[1:])]) @ v)), 3) for k, v in dirs.items()})
