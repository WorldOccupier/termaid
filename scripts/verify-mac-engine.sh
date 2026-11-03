#!/bin/sh
# Checks the native macOS engine end to end: bundled TS engine, Parakeet (FluidAudio) speech,
# and the GGUF in llama.cpp. First run downloads ~480 MB of speech models and builds for a few minutes.
# Usage: scripts/verify-mac-engine.sh [model.gguf]
set -eu
cd "$(dirname "$0")/.."
MODEL=${1:-training/gguf/lfm3-v10-q6_k.gguf}
BIN=mac/.build/release/termaid-mac
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

echo "1. TypeScript tests"
npm test >"$WORK/test.log" 2>&1 || { cat "$WORK/test.log"; fail "npm test"; }

echo "2. Bundle engine.js and build the Swift package"
npm run --silent build:engine >/dev/null
(cd mac && swift build -c release >"$WORK/build.log" 2>&1) || { tail -20 "$WORK/build.log"; fail "swift build"; }

echo "3. Speech: Parakeet transcribes a generated clip"
SENTENCE="Build, then test, then deploy."
say -o "$WORK/clip.aiff" "$SENTENCE"
afconvert -f WAVE -d LEI16@16000 -c 1 "$WORK/clip.aiff" "$WORK/clip.wav"
HEARD=$("$BIN" transcribe "$WORK/clip.wav" 2>/dev/null)
normalize() { echo "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z '; }
[ "$(normalize "$HEARD")" = "$(normalize "$SENTENCE")" ] || fail "heard \"$HEARD\", expected \"$SENTENCE\""
echo "   heard: $HEARD"

echo "4. Diagram: llama.cpp + engine produce valid Mermaid"
[ -f "$MODEL" ] || fail "model not found: $MODEL"
MERMAID=$("$BIN" diagram "$MODEL" "$HEARD" 2>/dev/null)
echo "$MERMAID" | head -1 | grep -q '^flowchart' || fail "no flowchart in output: $MERMAID"
for box in Build Test Deploy; do echo "$MERMAID" | grep -qi "\"$box" || fail "missing box $box"; done
echo "$MERMAID" | sed 's/^/   /'

echo "PASS: speech, engine and model all work natively"
