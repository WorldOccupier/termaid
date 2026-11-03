#!/bin/sh
# Runs the app's native pipeline (mac/.build/release/termaid-mac eval) on all 55 holdouts.
# usage: weight_space/run_eval.sh <model.gguf> <tag>   -> weight_space/results/<tag>-<holdout>.jsonl
set -e
cd "$(dirname "$0")/.."
BIN=../mac/.build/release/termaid-mac
for f in holdout holdout-complex holdout-complex-2 holdout-front; do
  "$BIN" eval "$1" "$f.txt" > "weight_space/results/$2-$f.jsonl"
done
