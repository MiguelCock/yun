#!/usr/bin/env bash
# Scaffolds a vendored tree-sitter grammar C3L from an upstream repository.
#
# Creates lib/tree_sitter_<name>.c3l/ (submodule + c3i + manifest + grammar.conf
# + queries + LICENSE + README), then adds the enum member and LanguageSpec entry
# in src/language.c3. Finish by building the grammar library and running c3c build.
#
# Usage:
#   scripts/add-tree-sitter-grammar.sh <name> --url <git-url> --module <mod> \
#       --function <fn> --extensions .a,.b [--rev <tag>] [--src <sub>] \
#       [--queries <sub>] [--license <file>] [--lsp-id <id>] \
#       [--lsp-command <cmd>] [--no-lsp]
#
# Example:
#   scripts/add-tree-sitter-grammar.sh rust \
#       --url https://github.com/tree-sitter/tree-sitter-rust \
#       --module tree_sitter_rust --function tree_sitter_rust --extensions .rs
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAME=""
URL=""
MODULE=""
FUNCTION=""
EXTENSIONS=""
REV=""
SRC="src"
QUERIES="queries"
LICENSE_FILE=""
LSP_ID=""
LSP_COMMAND=""
NO_LSP=0

if [ "$#" -lt 1 ]; then
	echo "usage: $0 <name> --url <git-url> --module <mod> --function <fn> --extensions .a,.b [--rev <tag>] [--src <sub>] [--queries <sub>] [--license <file>] [--lsp-id <id>] [--lsp-command <cmd>] [--no-lsp]" >&2
	exit 2
fi

NAME="$1"
shift

while [ "$#" -gt 0 ]; do
	case "$1" in
		--url) URL="$2"; shift 2 ;;
		--module) MODULE="$2"; shift 2 ;;
		--function) FUNCTION="$2"; shift 2 ;;
		--extensions) EXTENSIONS="$2"; shift 2 ;;
		--rev) REV="$2"; shift 2 ;;
		--src) SRC="$2"; shift 2 ;;
		--queries) QUERIES="$2"; shift 2 ;;
		--license) LICENSE_FILE="$2"; shift 2 ;;
		--lsp-id) LSP_ID="$2"; shift 2 ;;
		--lsp-command) LSP_COMMAND="$2"; shift 2 ;;
		--no-lsp) NO_LSP=1; shift ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

for required in URL MODULE FUNCTION EXTENSIONS; do
	if [ -z "${!required}" ]; then
		echo "missing --$(echo "$required" | tr '[:upper:]_' '[:lower:]-')" >&2
		exit 2
	fi
done

LIB="$ROOT/lib/tree_sitter_$NAME.c3l"
UPSTREAM="$LIB/upstream"
STEM="${NAME//_/-}"
LIBNAME="tree-sitter-$STEM"
ENUM="$(echo "$NAME" | tr '[:lower:]' '[:upper:]')"

if [ -e "$LIB" ]; then
	echo "$LIB already exists" >&2
	exit 1
fi

echo "adding submodule $URL -> $UPSTREAM"
git -C "$ROOT" submodule add "$URL" "lib/tree_sitter_$NAME.c3l/upstream"
if [ -n "$REV" ]; then
	git -C "$UPSTREAM" checkout "$REV"
	git -C "$ROOT" add "lib/tree_sitter_$NAME.c3l/upstream"
fi

mkdir -p "$LIB/queries"

printf 'module %s;\n\nimport tree_sitter;\n\nextern fn TSLanguage* %s();\n' "$MODULE" "$FUNCTION" >"$LIB/tree-sitter-$NAME.c3i"

cat >"$LIB/manifest.json" <<EOF
{
  "provides": "$MODULE",
  "linklib-dir": "linked-libs",
  "dependencies": [
    "tree_sitter"
  ],
  "targets": {
    "linux-x64": {
      "linked-libraries": [
        "$LIBNAME"
      ]
    },
    "macos-aarch64": {
      "linked-libraries": [
        "$LIBNAME"
      ]
    },
    "windows-x64": {
      "linked-libraries": [
        "$LIBNAME"
      ]
    }
  }
}
EOF

printf 'src = %s\nqueries = %s\nlib = %s\n' "$SRC" "$QUERIES" "$LIBNAME" >"$LIB/grammar.conf"

if [ -f "$UPSTREAM/$QUERIES/highlights.scm" ]; then
	cp "$UPSTREAM/$QUERIES/highlights.scm" "$LIB/queries/highlights.scm"
else
	echo "warning: $UPSTREAM/$QUERIES/highlights.scm not found; add queries/highlights.scm manually" >&2
fi

if [ -n "$LICENSE_FILE" ]; then
	cp "$LICENSE_FILE" "$LIB/LICENSE"
else
	for candidate in LICENSE LICENSE.md LICENSE.txt COPYING COPYING.txt COPYING.md; do
		if [ -f "$UPSTREAM/$candidate" ]; then
			cp "$UPSTREAM/$candidate" "$LIB/LICENSE"
			break
		fi
	done
fi

ABI="unknown"
if [ -f "$UPSTREAM/$SRC/parser.c" ]; then
	ABI="$(sed -n 's/^#define LANGUAGE_VERSION //p' "$UPSTREAM/$SRC/parser.c" | head -n 1)"
fi
REV_DESC="$(git -C "$UPSTREAM" describe --tags --always 2>/dev/null || true)"

cat >"$LIB/README.md" <<EOF
# tree_sitter_$NAME (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** \`$URL\`, pinned to \`$REV_DESC\`
- **Language ABI:** $ABI
- **Module:** \`$MODULE\`
- **License:** see \`LICENSE\`

## Layout

- \`tree-sitter-$NAME.c3i\` — declares \`$FUNCTION()\` returning the \`TSLanguage*\`.
- \`queries/highlights.scm\` — bundled highlight query, consumed by the editor.
- \`linked-libs/<target>/\` — built grammar library (shared by default; \`.a\` with \`--static\`).
- \`grammar.conf\` — build options (src/queries/lib) read by the build scripts.
- \`upstream/\` — the pinned grammar source (git submodule).

## Building

\`\`\`sh
scripts/build-tree-sitter.sh <target> $STEM
\`\`\`
EOF

# Wire src/language.c3: enum member and a LanguageSpec stub (lazy-loaded).
export YUN_ENUM="$ENUM"
export YUN_STEM="$STEM"
export YUN_FUNCTION="$FUNCTION"
export YUN_NAME="$NAME"
export YUN_EXTS="$EXTENSIONS"

perl -0777 -i -pe 's/\n(\tCOUNT,\n)/\n\t$ENV{YUN_ENUM},\n$1/' "$ROOT/src/language.c3"

SNIPPET_FILE="$(mktemp)"
{
	echo ""
	echo "	{"
	echo "		.name = \"$STEM\","
	exts=""
	IFS=',' read -ra EXTS <<<"$EXTENSIONS"
	for ext in "${EXTS[@]}"; do
		exts="$exts\"$ext\", "
	done
	exts="${exts%, }"
	echo "		.extensions = { $exts },"
	echo "		.lib = \"$LIBNAME\","
	echo "		.symbol = \"$FUNCTION\","
	echo "		.highlights_path = \"lib/tree_sitter_$NAME.c3l/queries/highlights.scm\","
	echo "		.import_query = \"\","
	echo "		.module_query = \"\","
	echo "		.symbols_query = \"\","
	echo "	},"
} >"$SNIPPET_FILE"

SNIP="$SNIPPET_FILE" perl -0777 -i -pe 'BEGIN { open my $f, "<", $ENV{SNIP}; local $/; $s = <$f>; close $f; } s/(\n\};\n\nfn String path_extension)/$s . $1/e' "$ROOT/src/language.c3"
rm -f "$SNIPPET_FILE"

# Wire the LSP table (unless disabled or the id already exists).
if [ "$NO_LSP" -eq 0 ] && [ -n "$LSP_COMMAND" ]; then
	[ -z "$LSP_ID" ] && LSP_ID="$STEM"
	if grep -q "\.id = \"$LSP_ID\"" "$ROOT/src/language.c3"; then
		echo "note: LSP id \"$LSP_ID\" already present; skipping LSP entry"
	else
		LSP_SNIPPET_FILE="$(mktemp)"
		LSP_COMMAND_ESC="$(printf '%s' "$LSP_COMMAND" | sed 's/\\/\\\\/g; s/"/\\"/g')"
		{
			echo ""
			echo "	{"
			echo "		.id = \"$LSP_ID\","
			echo "		.extensions = { $exts },"
			echo "		.command = \"$LSP_COMMAND_ESC\","
			echo "	},"
		} >"$LSP_SNIPPET_FILE"
		SNIP="$LSP_SNIPPET_FILE" perl -0777 -i -pe 'BEGIN { open my $f, "<", $ENV{SNIP}; local $/; $s = <$f>; close $f; } s/(\n\};\n\nfn String lsp_for_path)/$s . $1/e' "$ROOT/src/language.c3"
		rm -f "$LSP_SNIPPET_FILE"
	fi
fi

echo "created $LIB"
echo "next:"
echo "  1. scripts/build-tree-sitter.sh linux-x64 $STEM"
echo "  2. review the LanguageSpec entry in src/language.c3 (fill import/module/symbols queries if any)"
echo "  3. c3c build && c3c test"
