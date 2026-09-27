#!/usr/bin/env bash
# Checks each vendored tree-sitter grammar's Language ABI against the pinned
# runtime. Exits non-zero on an incompatible grammar.
#
# Usage: scripts/check-tree-sitter-abi.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
API="$ROOT/lib/tree_sitter.c3l/upstream/lib/include/tree_sitter/api.h"

read_conf() {
	local file="$1"
	local key="$2"
	local fallback="$3"
	local value=""
	if [ -f "$file" ]; then
		value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$file" | head -n 1 | tr -d '[:space:]')"
	fi
	if [ -z "$value" ]; then echo "$fallback"; else echo "$value"; fi
}

if [ ! -f "$API" ]; then
	echo "warning: runtime header not found at $API" >&2
	echo "run: git submodule update --init lib/tree_sitter.c3l/upstream" >&2
	exit 0
fi

RUNTIME_ABI="$(sed -n 's/^#define TREE_SITTER_LANGUAGE_VERSION //p' "$API" | head -n 1)"
RUNTIME_MIN="$(sed -n 's/^#define TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION //p' "$API" | head -n 1)"
echo "runtime: ABI $RUNTIME_ABI (min compatible $RUNTIME_MIN)"

status=0
printf '%-16s %-6s %s\n' "grammar" "ABI" "result"
for dep in "$ROOT"/lib/tree_sitter_*.c3l; do
	[ -d "$dep" ] || continue
	base="$(basename "$dep")"
	[ "$base" = "tree_sitter.c3l" ] && continue

	stem="${base#tree_sitter_}"
	stem="${stem%.c3l}"
	stem="${stem//_/-}"
	src="$(read_conf "$dep/grammar.conf" src src)"
	parser="$dep/upstream/$src/parser.c"

	if [ ! -f "$parser" ]; then
		printf '%-16s %-6s %s\n' "$stem" "-" "missing $parser (init submodule?)"
		status=1
		continue
	fi

	abi="$(sed -n 's/^#define LANGUAGE_VERSION //p' "$parser" | head -n 1)"
	if [ -z "$abi" ]; then
		printf '%-16s %-6s %s\n' "$stem" "?" "no LANGUAGE_VERSION in parser.c"
		status=1
		continue
	fi

	if [ "$abi" -gt "$RUNTIME_ABI" ]; then
		printf '%-16s %-6s %s\n' "$stem" "$abi" "INCOMPATIBLE (grammar > runtime)"
		status=1
	elif [ "$abi" -lt "$RUNTIME_MIN" ]; then
		printf '%-16s %-6s %s\n' "$stem" "$abi" "INCOMPATIBLE (grammar < min compatible)"
		status=1
	else
		printf '%-16s %-6s %s\n' "$stem" "$abi" "ok"
	fi
done

exit "$status"
