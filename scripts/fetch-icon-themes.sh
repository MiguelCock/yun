#!/usr/bin/env bash
# Regenerate the vendored VS Code icon themes.
#
# Pinned sources:
#   Codicons                  microsoft/vscode-codicons
#   Material Icon Theme       PKief/vscode-material-icon-theme
#   vscode-icons              vscode-icons/vscode-icons
#
# Requires: git, curl, tar, rsvg-convert.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/assets/icons"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

command -v rsvg-convert >/dev/null || {
	echo "rsvg-convert is required (librsvg2-bin)" >&2
	exit 1
}

CODICONS_REV=8d1826a9bce0a52283ecaeb63499c149e97a4f14
MATERIAL_REV=3929c5487ca03352f31cfba675b367448449094d
VSCODE_REV=aba557c553d86d671db448f3b249afb6ae30e151

fetch() {
	local name=$1 rev=$2
	curl -fsSL -o "$TMP/$name.tar.gz" "https://github.com/$name/archive/$rev.tar.gz"
	tar -xzf "$TMP/$name.tar.gz" -C "$TMP"
}

fetch microsoft/vscode-codicons "$CODICONS_REV"
fetch PKief/vscode-material-icon-theme "$MATERIAL_REV"
fetch vscode-icons/vscode-icons "$VSCODE_REV"

CODICONS="$TMP/vscode-codicons-$CODICONS_REV"
MATERIAL="$TMP/vscode-material-icon-theme-$MATERIAL_REV"
VSCODE="$TMP/vscode-icons-$VSCODE_REV"

mkdir -p "$OUT/codicons" "$OUT/material" "$OUT/vscode"

# UI icons: rasterize Codicons as white silhouettes so they can be tinted.
CODICON_ICONS=(
	new-file:new-file open:folder-opened save:save settings:gear
	connections:plug quit:debug-disconnect preview:eye
	maximize:screen-full restore:screen-normal minimize:chevron-down
	close:close search:search problems:warning symbols:symbol-class
	console:terminal git:source-control keyboard:key theme:color-mode play:play
	stop:stop-circle trash:trash
	chevron-down:chevron-down chevron-right:chevron-right
)
for entry in "${CODICON_ICONS[@]}"; do
	logical=${entry%%:*}
	source_name=${entry#*:}
	sed 's/currentColor/#FFFFFF/g' "$CODICONS/src/icons/$source_name.svg" > "$TMP/icon.svg"
	rsvg-convert -w 48 -h 48 -o "$OUT/codicons/$logical.png" "$TMP/icon.svg"
done

MATERIAL_ICONS=(
	c3 c python javascript go rust zig odin nim cpp java kotlin scala csharp
	typescript css html lua php ruby r julia haskell gleam erlang elixir dart markdown
)
for name in "${MATERIAL_ICONS[@]}"; do
	rsvg-convert -w 48 -h 48 -o "$OUT/material/$name.png" "$MATERIAL/icons/$name.svg"
done
rsvg-convert -w 48 -h 48 -o "$OUT/material/file.png" "$MATERIAL/icons/document.svg"
rsvg-convert -w 48 -h 48 -o "$OUT/material/folder.png" "$MATERIAL/icons/folder-base.svg"
cp "$OUT/material/folder.png" "$OUT/material/folder-open.png"

VSCODE_ICONS=(
	file_type_c3 file_type_c file_type_python file_type_js file_type_go
	file_type_rust file_type_zig file_type_nim file_type_cpp file_type_java
	file_type_kotlin file_type_scala file_type_csharp file_type_typescript
	file_type_css file_type_html file_type_lua file_type_php file_type_ruby
	file_type_r file_type_julia file_type_haskell file_type_gleam file_type_erlang
	file_type_elixir file_type_dartlang file_type_markdown
	default_file default_folder default_folder_opened
)
for name in "${VSCODE_ICONS[@]}"; do
	rsvg-convert -w 48 -h 48 -o "$OUT/vscode/$name.png" "$VSCODE/icons/$name.svg"
done

cp "$CODICONS/LICENSE" "$OUT/LICENSE-codicons"
cp "$MATERIAL/LICENSE" "$OUT/LICENSE-material"
cp "$VSCODE/LICENSE" "$OUT/LICENSE-vscode-icons"

echo "icon themes regenerated in $OUT"
