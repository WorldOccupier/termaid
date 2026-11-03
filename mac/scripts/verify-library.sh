#!/usr/bin/env bash
# Builds Termaid, opens the Library (grid, the newest diagram's detail view, then the same with the info panel open),
# screenshots only the Library window, and checks the layout.
# Usage: scripts/verify-library.sh   (from mac/). Screenshots land in /tmp/termaid-library-*.png
set -euo pipefail
cd "$(dirname "$0")/.."
MODEL="${TERMAID_MODEL:-$PWD/../training/gguf/lfm3-v10-q6_k.gguf}"
fail() { echo "FAIL: $*"; exit 1; }

echo "• swift build"; swift build 2>&1 | grep -q "Build complete" || fail "swift build"
echo "• building Termaid.app"; scripts/build-app.sh >/dev/null

for mode in grid detail info; do
  pkill -f Termaid.app || true; sleep 1
  open --env TERMAID_MODEL="$MODEL" --env TERMAID_SHOW_LIBRARY=$mode build/Termaid.app
  id=""
  for _ in $(seq 1 20); do id=$(swift scripts/library-winid.swift 2>/dev/null || true); [ -n "$id" ] && break; sleep 0.5; done
  [ -n "$id" ] || fail "$mode: Library window never appeared"
  sleep 1.5  # let the slide-in finish
  out=/tmp/termaid-library-$mode.png
  screencapture -o -l "$id" "$out"
  python3 - "$out" "$mode" <<'PY' || exit 1
import sys, struct, zlib
path, mode = sys.argv[1], sys.argv[2]
# Minimal PNG decode (RGBA/RGB, 8-bit) — no third-party deps.
d = open(path, 'rb').read(); pos = 8; w = h = ct = 0; idat = b''
while pos < len(d):
    n, = struct.unpack('>I', d[pos:pos+4]); t = d[pos+4:pos+8]; c = d[pos+8:pos+8+n]
    if t == b'IHDR': w, h, _, ct = struct.unpack('>IIBB', c[:10])
    if t == b'IDAT': idat += c
    pos += 12 + n
bpp = 4 if ct == 6 else 3; raw = zlib.decompress(idat); stride = w*bpp; rows = []; prev = bytearray(stride); i = 0
for _ in range(h):
    f = raw[i]; line = bytearray(raw[i+1:i+1+stride]); i += 1+stride
    for x in range(stride):
        a = line[x-bpp] if x >= bpp else 0; b = prev[x]; c = prev[x-bpp] if x >= bpp else 0
        if f == 1: line[x] = (line[x]+a) & 255
        elif f == 2: line[x] = (line[x]+b) & 255
        elif f == 3: line[x] = (line[x]+(a+b)//2) & 255
        elif f == 4:
            p = a+b-c; pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
            line[x] = (line[x]+(a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
    rows.append(line); prev = line
px = lambda x, y: tuple(rows[y][x*bpp:x*bpp+3])
s = w / 1040  # screenshot scale (Retina = 2)
def check(ok, msg):
    print(("  ✓ " if ok else "  ✗ ") + f"{mode}: {msg}")
    if not ok: sys.exit(1)
check(w > 600 and h > 400, f"window captured at {w}x{h}")
# Dark Obsidian canvas in the middle-left area.
r, g, b = px(int(40*s), int(h*0.85)); check(max(r, g, b) < 40, f"canvas is near-black ({r},{g},{b})")
if mode == "detail":
    # Info closed by default: no card in the right column, an info button in the bottom-right corner.
    # (no bright title text where the card's title would sit, y ≈ 85–145pt)
    text = sum(1 for x in range(int(w*0.73), int(w*0.97), 2) for y in range(int(85*s), int(145*s), 2) if sum(px(x, y)) > 400)
    check(text == 0, f"info panel hidden by default ({text} bright px)")
    btn = any(sum(px(x, y)) > 300 for x in range(w-int(44*s), w-int(16*s)) for y in range(h-int(44*s), h-int(16*s), 2))
    check(btn, "info button in the bottom-right corner")
if mode in ("detail", "info"):
    # Back button sits in its own row under the traffic lights, left edge aligned with them (x≈15pt, y≈45pt).
    row = int(45*s); hit = any(sum(px(x, row)) > 300 for x in range(int(18*s), int(34*s)))
    check(hit, "back button is under the traffic lights, aligned with their left edge")
    top = int(18*s); clear = not any(sum(px(x, top)) > 300 for x in range(int(80*s), int(110*s)))
    check(clear, "title-bar row beside the traffic lights is empty")
if mode == "info":
    # The side card stacks title, Copy/Save, then "You said". "You said" is a neutral read-only box: no blue accent
    # from the actions down through the prompt (y ≈ 170–360pt).
    xs = range(int(w*0.70), int(w*0.98), 2)
    blue = [y for y in range(int(170*s), int(360*s)) if any((lambda p: p[2] > 150 and p[2] > p[0]+60)(px(x, y)) for x in xs)]
    check(not blue, f"no blue accent in the actions or description area ({len(blue)} rows)")
    # The card hugs its content: low in the panel column there is bare canvas (≈6), not the card's lighter fill (≈16).
    low = max(max(px(x, int(h*0.85))) for x in range(int(w*0.72), int(w*0.97), 2))
    check(low < 12, f"side card hugs its content, no empty card below it (max {low})")
PY
done
pkill -f Termaid.app || true
echo "PASS — screenshots: /tmp/termaid-library-{grid,detail,info}.png"
