#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${1:-$root/.yun/visual-out}"
project="$(mktemp -d)"
trap 'rm -rf "$project"' EXIT

mkdir -p "$project/src"
cat > "$project/src/demo.c3" <<'C3'
module demo;

import std::io;

fn void hello()
{
	io::printn("hello");
}
C3
cat > "$project/README.md" <<'MD'
# Visual fixture

This project exists only for deterministic UI screenshots.
MD
printf '{\n  "name": "visual-fixture"\n}\n' > "$project/package.json"
git -C "$project" init -q

(cd "$root" && c3c build)

"$root/build/yun" "$project" --visual-suite="$out" >/tmp/yun-visual-suite.log 2>&1

expected=(
	canvas
	settings
	connections
	source-control
	console
	problems
	search
	symbols
	palette
	browser
	topbar-bottom
	topbar-left
	topbar-right
	notifications
)

for name in "${expected[@]}"; do
	if [[ ! -s "$out/$name.png" ]]; then
		echo "missing visual state: $name.png" >&2
		exit 1
	fi
done

python3 - "$out" "${expected[@]}" <<'PY'
import struct
import sys
from pathlib import Path

out = Path(sys.argv[1])
failed = False
for name in sys.argv[2:]:
    path = out / f"{name}.png"
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
        print(f"not a PNG: {path}", file=sys.stderr)
        failed = True
        continue
    width, height = struct.unpack(">II", data[16:24])
    if width <= 0 or height <= 0:
        print(f"invalid dimensions: {path} {width}x{height}", file=sys.stderr)
        failed = True
    else:
        print(f"{name}: {width}x{height}")
if failed:
    raise SystemExit(1)
PY

echo "visual suite passed: $out"
