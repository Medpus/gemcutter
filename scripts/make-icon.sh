#!/usr/bin/env bash
# Lager Gemcutter/Media/Icon.tga (64x64) og assets/logo-400.png fra assets/icon.svg.
# TGA skrives for hånd: ukomprimert BGRA, origo nede til venstre (som WoW-ikonene i Forever).
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# Spillikonet får gjennomsiktig bakgrunn: fjern flaten og snittlinjen
grep -v 'id="bg"\|id="cutline"' assets/icon.svg > "$tmp/icon.svg"
magick -background none -density 768 "$tmp/icon.svg" -resize 64x64 -depth 8 rgba:"$tmp/icon.rgba"
python3 -I - "$tmp/icon.rgba" Gemcutter/Media/Icon.tga <<'PY'
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
w = h = 64
data = open(src, "rb").read()
assert len(data) == w * h * 4
rows = [data[y * w * 4:(y + 1) * w * 4] for y in range(h)]
out = bytearray(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 8))
for row in reversed(rows):
    for i in range(0, len(row), 4):
        r, g, b, a = row[i:i + 4]
        out += bytes((b, g, r, a))
open(dst, "wb").write(out)
PY
magick -background none -density 4800 assets/icon.svg -resize 400x400 assets/logo-400.png
echo "Laget Gemcutter/Media/Icon.tga og assets/logo-400.png"
