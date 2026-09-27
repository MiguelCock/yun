#!/usr/bin/env bash
# Verifies every vendored tree-sitter grammar C3L is well-formed: it has a c3i,
# manifest, highlight query, README, LICENSE, and a committed linux-x64 library.
#
# Usage: scripts/check-tree-sitter-grammars.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
status=0

for dep in "$ROOT"/lib/tree_sitter_*.c3l; do
	[ -d "$dep" ] || continue
	base="$(basename "$dep")"
	[ "$base" = "tree_sitter.c3l" ] && continue

	missing=()
	compgen -G "$dep/*.c3i" >/dev/null || missing+=("c3i")
	[ -f "$dep/manifest.json" ] || missing+=("manifest.json")
	[ -f "$dep/queries/highlights.scm" ] || missing+=("queries/highlights.scm")
	[ -f "$dep/README.md" ] || missing+=("README.md")
	[ -f "$dep/LICENSE" ] || missing+=("LICENSE")
	compgen -G "$dep/linked-libs/linux-x64/lib*.a" >/dev/null || missing+=("linked-libs/linux-x64/lib*.a")

	if [ "${#missing[@]}" -eq 0 ]; then
		echo "ok: $base"
	else
		echo "FAIL: $base missing ${missing[*]}"
		status=1
	fi
done

exit "$status"
