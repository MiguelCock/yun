#!/usr/bin/env bash
# Builds the tree-sitter runtime and grammar static libraries for one target.
#
# Pinned upstream sources live in the git submodules under
# lib/tree-sitter*.c3l/upstream. This script compiles them into
# linked-libs/<target>/ so that `c3c build` can link them.
#
# Usage:
#   scripts/build-tree-sitter.sh [target]
#
# target defaults to linux-x64. macos-aarch64 / windows-x64 can be produced by
# running the same logic with a matching cross toolchain (documented, not
# automated here -- see README.md in each lib).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-linux-x64}"
CC="${CC:-cc}"
AR="${AR:-ar}"
CFLAGS="${CFLAGS:--O2 -fPIC}"

# runtime: name:submodule-dir:output
RUNTIME_DIR="$ROOT/lib/tree_sitter.c3l/upstream"
RUNTIME_INCLUDE="$RUNTIME_DIR/lib/include"

build_lib() {
	local name="$1"
	local dir="$2"
	local out="$3"

	local work="$dir"
	local objects=()
	pushd "$work" >/dev/null

	local src_root="src"
	local sources=("$src_root/parser.c")
	[ -f "$src_root/scanner.c" ] && sources+=("$src_root/scanner.c")
	[ -f "$src_root/scanner.cc" ] && sources+=("$src_root/scanner.cc")

	local i=0
	for src in "${sources[@]}"; do
		local obj="$out/$name-$i.o"
		"$CC" $CFLAGS -I"$RUNTIME_INCLUDE" -I"$work/$src_root" -c "$src" -o "$obj"
		objects+=("$obj")
		i=$((i + 1))
	done
	popd >/dev/null

	"$AR" rcs "$out/lib$name.a" "${objects[@]}"
	rm -f "${objects[@]}"
	echo "built $out/lib$name.a"
}

runtime_out="$ROOT/lib/tree_sitter.c3l/linked-libs/$TARGET"
mkdir -p "$runtime_out"
echo "building tree-sitter runtime for $TARGET"
"$CC" $CFLAGS -I"$RUNTIME_INCLUDE" -c "$RUNTIME_DIR/lib/src/lib.c" -o "$runtime_out/libtree-sitter.o"
"$AR" rcs "$runtime_out/libtree-sitter.a" "$runtime_out/libtree-sitter.o"
rm -f "$runtime_out/libtree-sitter.o"
echo "built $runtime_out/libtree-sitter.a"

build_dep() {
	local name="$1"
	local dep="$2"
	local sub="$ROOT/lib/$dep/upstream"
	local out="$ROOT/lib/$dep/linked-libs/$TARGET"
	mkdir -p "$out"
	echo "building $name for $TARGET"
	build_lib "$name" "$sub" "$out"
}

build_dep tree-sitter-c tree_sitter_c.c3l
build_dep tree-sitter-python tree_sitter_python.c3l
build_dep tree-sitter-javascript tree_sitter_javascript.c3l
build_dep tree-sitter-c3 tree_sitter_c3.c3l

echo "done ($TARGET)"
