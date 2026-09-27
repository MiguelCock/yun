#!/usr/bin/env bash
# Builds the tree-sitter runtime and grammar libraries for one target.
#
# Grammars are discovered from lib/tree_sitter_*.c3l (each with an upstream/
# submodule). Optional per-grammar options live in that directory's
# grammar.conf (key=value): src, queries, lib. Defaults: src=src, queries=queries,
# lib=tree-sitter-<stem>.
#
# Usage:
#   scripts/build-tree-sitter.sh [--static] [target] [grammar...]
#
# The runtime is always built as a static library (linked into the executable).
# Grammars build as shared libraries by default (loaded lazily at runtime);
# --static builds grammar .a libraries instead (for static linking).
#
# target defaults to linux-x64. The remaining args filter by grammar stem
# (e.g. `python c3`); with none, every grammar is built.
#
# macos-aarch64 / windows-x64 can be produced with a matching cross toolchain
# (documented, not automated here -- see docs/tree-sitter.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="shared"
POSITIONAL=()
for arg in "$@"; do
	case "$arg" in
		--static) MODE="static" ;;
		--shared) MODE="shared" ;;
		*) POSITIONAL+=("$arg") ;;
	esac
done

TARGET="${POSITIONAL[0]:-linux-x64}"
FILTER=()
if [ "${#POSITIONAL[@]}" -gt 1 ]; then
	FILTER=("${POSITIONAL[@]:1}")
fi

CC="${CC:-cc}"
CXX="${CXX:-c++}"
AR="${AR:-ar}"
CFLAGS="${CFLAGS:--O2 -fPIC}"

RUNTIME_DIR="$ROOT/lib/tree_sitter.c3l/upstream"
RUNTIME_INCLUDE="$RUNTIME_DIR/lib/include"

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

selected() {
	local stem="$1"
	[ "${#FILTER[@]}" -eq 0 ] && return 0
	for want in "${FILTER[@]}"; do
		[ "$want" = "$stem" ] && return 0
	done
	return 1
}

build_lib() {
	local name="$1"
	local upstream="$2"
	local src_root="$3"
	local out="$4"

	local work="$upstream"
	local objects=()
	pushd "$work" >/dev/null

	local sources=()
	[ -f "$src_root/parser.c" ] && sources+=("$src_root/parser.c")
	[ -f "$src_root/scanner.c" ] && sources+=("$src_root/scanner.c")
	[ -f "$src_root/scanner.cc" ] && sources+=("$src_root/scanner.cc")

	if [ "${#sources[@]}" -eq 0 ]; then
		popd >/dev/null
		echo "warning: no parser.c under $upstream/$src_root; skipping $name" >&2
		return 0
	fi

	local i=0
	for src in "${sources[@]}"; do
		local obj="$out/$name-$i.o"
		local compiler="$CC"
		case "$src" in
			*.cc|*.cpp) compiler="$CXX" ;;
		esac
		"$compiler" $CFLAGS -I"$RUNTIME_INCLUDE" -I"$work/$src_root" -c "$src" -o "$obj"
		objects+=("$obj")
		i=$((i + 1))
	done
	popd >/dev/null

	if [ "$MODE" = "shared" ]; then
		"$CC" $CFLAGS -shared -o "$out/lib$name.so" "${objects[@]}"
		echo "built $out/lib$name.so"
	else
		"$AR" rcs "$out/lib$name.a" "${objects[@]}"
		echo "built $out/lib$name.a"
	fi
	rm -f "${objects[@]}"
}

runtime_out="$ROOT/lib/tree_sitter.c3l/linked-libs/$TARGET"
mkdir -p "$runtime_out"
echo "building tree-sitter runtime for $TARGET"
"$CC" $CFLAGS -I"$RUNTIME_INCLUDE" -c "$RUNTIME_DIR/lib/src/lib.c" -o "$runtime_out/libtree-sitter.o"
"$AR" rcs "$runtime_out/libtree-sitter.a" "$runtime_out/libtree-sitter.o"
rm -f "$runtime_out/libtree-sitter.o"
echo "built $runtime_out/libtree-sitter.a"

for dep in "$ROOT"/lib/tree_sitter_*.c3l; do
	[ -d "$dep" ] || continue
	base="$(basename "$dep")"
	[ "$base" = "tree_sitter.c3l" ] && continue

	stem="${base#tree_sitter_}"
	stem="${stem%.c3l}"
	stem="${stem//_/-}"

	selected "$stem" || continue

	conf="$dep/grammar.conf"
	src_root="$(read_conf "$conf" src src)"
	lib="$(read_conf "$conf" lib "tree-sitter-$stem")"

	out="$dep/linked-libs/$TARGET"
	mkdir -p "$out"
	echo "building $lib for $TARGET ($MODE)"
	build_lib "$lib" "$dep/upstream" "$src_root" "$out"
done

echo "done ($TARGET)"
