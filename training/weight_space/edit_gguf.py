"""Directional ablation in the MLP output weights of an f16 GGUF, written to a copy.

usage (via uv, gguf-py is not in training/.venv):
  uv run --no-project --with gguf --with numpy python edit_gguf.py SRC.gguf DST.gguf DIRS.npz \
      --layers 12,15 [--alpha 1.0] [--topk 64]

DIRS.npz holds one residual-space direction per layer ("L12" -> (2048,)). In LFM3 the MLP writes
post_ffw_norm(ffn_down(x)) = g * y / rms(y) into the residual, so removing direction d from what
the residual receives means removing u = normalize(g * d) from y: W_down <- W_down - alpha * u u^T W_down,
over all input columns (7680 neurons; with --target attn the 2048 attn_output inputs) or only the --topk columns that write most along u.
SRC is never opened for writing: DST starts as an APFS clone (cp -c) and only DST is patched.
"""
import argparse
import subprocess
from pathlib import Path

import numpy as np
from gguf import GGUFReader


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("dirs")
    ap.add_argument("--layers", required=True)
    ap.add_argument("--alpha", type=float, default=1.0)
    ap.add_argument("--topk", type=int, default=0)
    ap.add_argument("--target", choices=["ffn", "attn", "all"], default="ffn",
                    help="ffn: ffn_down (+post_ffw_norm); attn: attn_output or shortconv.out_proj (+post_attention_norm); all: both")
    a = ap.parse_args()
    src, dst = Path(a.src).resolve(), Path(a.dst).resolve()
    assert src != dst and not dst.exists(), "refusing to overwrite"
    subprocess.run(["cp", "-c", str(src), str(dst)], check=True)
    dirs = np.load(a.dirs)
    r = GGUFReader(str(dst), "r+")
    tensors = {t.name: t for t in r.tensors}
    changed = 0
    for layer in [int(x) for x in a.layers.split(",")]:
        d = dirs[f"L{layer}"].astype(np.float64)
        writers = []
        if a.target in ("ffn", "all"):
            writers.append(("post_ffw_norm", "ffn_down"))
        if a.target in ("attn", "all"):
            writers.append(("post_attention_norm", "attn_output" if f"blk.{layer}.attn_output.weight" in tensors else "shortconv.out_proj"))
        for norm, mat in writers:
            g = np.asarray(tensors[f"blk.{layer}.{norm}.weight"].data, dtype=np.float64)
            u = g * d
            u /= np.linalg.norm(u)
            W = tensors[f"blk.{layer}.{mat}.weight"].data  # (2048 out, n in) float16 memmap
            Wf = np.asarray(W, dtype=np.float64)
            proj = u @ Wf  # (7680,) how much each neuron writes along u
            cols = np.argsort(-np.abs(proj))[: a.topk] if a.topk else np.arange(Wf.shape[1])
            Wf[:, cols] -= a.alpha * np.outer(u, proj[cols])
            W[:, cols] = Wf[:, cols].astype(np.float16)
            changed += W.shape[0] * len(cols)
            share = (proj[cols] ** 2).sum() / (proj ** 2).sum()
            print(f"layer {layer} {mat}: {len(cols)} columns, {W.shape[0] * len(cols)} weights, "
                  f"{share:.1%} of the layer's write along u, |g|mean={np.abs(g).mean():.3f}")
    r.data.flush()
    print(f"total weights changed: {changed}")


if __name__ == "__main__":
    main()
