#!/usr/bin/env bash
# Builds a static Lua 5.4 library for one target.
#
# Usage:
#   scripts/build-lua.sh [--static] [target]
#
# target defaults to linux-x64. Output:
#   lib/lua54.c3l/linked-libs/<target>/liblua54.a
#
# Lua source lives in lib/lua54.c3l/upstream (pinned submodule).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="static"
POSITIONAL=()
for arg in "$@"; do
	case "$arg" in
		--static) MODE="static" ;;
		--shared) MODE="shared" ;;
		*) POSITIONAL+=("$arg") ;;
	esac
done
TARGET="${POSITIONAL[0]:-linux-x64}"
UPSTREAM="$ROOT/lib/lua54.c3l/upstream"
OUT="$ROOT/lib/lua54.c3l/linked-libs/$TARGET"
CC="${CC:-cc}"
AR="${AR:-ar}"
CFLAGS="${CFLAGS:--O2 -fPIC}"

if [ ! -f "$UPSTREAM/lapi.c" ]; then
	echo "missing Lua source under $UPSTREAM" >&2
	echo "run: git submodule update --init --recursive" >&2
	exit 1
fi

case "$TARGET" in
	linux-*)
		PLATFORM_FLAGS="-DLUA_USE_POSIX"
		;;
	macos-*)
		PLATFORM_FLAGS="-DLUA_USE_POSIX"
		;;
	windows-*)
		PLATFORM_FLAGS="-DLUA_USE_WINDOWS"
		;;
	*)
		PLATFORM_FLAGS="-DLUA_USE_POSIX"
		;;
esac

SOURCES=(
	lapi.c lauxlib.c lbaselib.c lcode.c lcorolib.c lctype.c ldblib.c
	ldebug.c ldo.c ldump.c lfunc.c lgc.c linit.c liolib.c llex.c
	lmathlib.c lmem.c loadlib.c lobject.c lopcodes.c loslib.c lparser.c
	lstate.c lstring.c lstrlib.c ltable.c ltablib.c ltm.c lundump.c
	lutf8lib.c lvm.c lzio.c
)

mkdir -p "$OUT"
OBJECTS=()
cleanup() {
	rm -f "${OBJECTS[@]}"
}
trap cleanup EXIT

for src in "${SOURCES[@]}"; do
	obj="$OUT/lua54-${src%.c}.o"
	"$CC" $CFLAGS $PLATFORM_FLAGS -I"$UPSTREAM" -c "$UPSTREAM/$src" -o "$obj"
	OBJECTS+=("$obj")
done

if [ "$MODE" = "shared" ]; then
	"$CC" $CFLAGS -shared -o "$OUT/liblua54.so" "${OBJECTS[@]}"
	echo "built $OUT/liblua54.so"
else
	"$AR" rcs "$OUT/liblua54.a" "${OBJECTS[@]}"
	echo "built $OUT/liblua54.a"
fi
