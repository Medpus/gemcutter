#!/usr/bin/env bash
# Alt som skal være grønt før commit og release. Kjøres lokalt, ikke i CI.
set -euo pipefail
cd "$(dirname "$0")/.."
luajit tests/run.lua
luajit tests/ui_smoke.lua
for f in Gemcutter/*.lua; do luajit -bl "$f" > /dev/null; done
# LuaJIT godtar goto, men WoW (Lua 5.1) gjør det ikke
if grep -nE '\bgoto\b' Gemcutter/*.lua; then echo "goto i addonfil"; exit 1; fi
echo "Alt grønt"
