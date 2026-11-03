"""Diff-in-means direction for orphan vs connected source decisions, per layer, with a cross-split check.

usage: python analyze.py <contrast_dir> [--ref LAYER] [--save dirs.npz]
Prints for each layer: separation (AUC) of l_out projected on the direction fit on the other split,
and how much the layer's MLP write (ffn) differs between classes along the reference direction.
"""
import argparse
import json
from pathlib import Path

import numpy as np


def load(d):
    meta = json.loads((d / "meta.json").read_text())
    X, y, src = [], [], []
    for i, m in enumerate(meta):
        js = json.loads((d / "acts" / f"{i}.json").read_text())
        a = np.fromfile(d / "acts" / f"{i}.f16", dtype=np.float16).astype(np.float32)
        a = a.reshape(js["rows"], len(js["keys"]), js["n_embd"])
        X.append(a)
        y += m["labels"]
        src += [m["src"]] * len(m["labels"])
    return np.concatenate(X), np.array(y), np.array(src), js["keys"]


def auc(s, y):
    pos, neg = s[y == 1], s[y == 0]
    return (pos[:, None] > neg[None, :]).mean() + 0.5 * (pos[:, None] == neg[None, :]).mean()


def dim(X, y):
    d = X[y == 1].mean(0) - X[y == 0].mean(0)
    return d / np.linalg.norm(d)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--ref", type=int, default=None)
    ap.add_argument("--save")
    ap.add_argument("--layers", default="")
    a = ap.parse_args()
    X, y, src, keys = load(Path(a.dir))
    nL = len(keys) // 2
    splits = sorted(set(src))
    print(f"n={len(y)} orphan={y.sum()} splits={[(s.split('/')[-1][:20], int((src == s).sum())) for s in splits]}")
    print("layer  AUC(l_out, cross-split)  AUC(ffn)  |mean diff l_out|  ffn write along ref-dir (orphan-connected)")
    ref = a.ref
    dref = dim(X[:, ref], y) if ref is not None else None
    for L in range(nL):
        res, ffn = X[:, L], X[:, nL + L]
        aucs, aucf = [], []
        for s in splits:
            tr, te = src != s, src == s
            aucs.append(auc(res[te] @ dim(res[tr], y[tr]), y[te]))
            aucf.append(auc(ffn[te] @ dim(ffn[tr], y[tr]), y[te]))
        md = np.linalg.norm(res[y == 1].mean(0) - res[y == 0].mean(0))
        w = ""
        if dref is not None:
            p = ffn @ dref
            w = f"{p[y == 1].mean() - p[y == 0].mean():+8.2f}"
        print(f"{L:5d}  {np.mean(aucs):.3f} ({' '.join(f'{x:.2f}' for x in aucs)})   {np.mean(aucf):.3f}   {md:8.2f}   {w}")
    if a.save:
        out = {}
        for L in [int(x) for x in a.layers.split(",")]:
            out[f"L{L}"] = dref  # the residual direction at the reference layer, removed from MLP L's write
        np.savez(a.save, **out)
        print("saved", a.save, list(out))


if __name__ == "__main__":
    main()
