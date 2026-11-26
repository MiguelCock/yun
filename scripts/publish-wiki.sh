#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="${1:-MiguelCock/yun}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! git clone -q "https://github.com/${repo}.wiki.git" "$tmp/wiki" 2>/dev/null; then
	cat >&2 <<'EOF'
GitHub creates the wiki git repository only after the first page exists.

Open https://github.com/MiguelCock/yun/wiki in a browser, choose
"Create the first page", give it the title "Home", and save any body.
Then run this script again.
EOF
	exit 1
fi

cd "$tmp/wiki"
cp "$root/docs/guide/"*.md .
cat > Home.md <<'EOF'
# Yun

Yun is a canvas-based code IDE. Files are movable cards and folders are clusters
on an infinite pan/zoom canvas.

This wiki mirrors the user guide in the repository. The canonical, versioned
copy lives in [docs/guide](https://github.com/MiguelCock/yun/tree/main/docs/guide).

- [Getting started](getting-started.md)
- [Canvas and navigation](canvas.md)
- [Editing](editing.md)
- [Search and connections](search.md)
- [Import arrows](imports.md)
- [Git](git.md)
- [Console](console.md)
- [Language servers](lsp.md)
- [Mods](mods.md)
- [Settings and keybindings](settings.md)
- [Troubleshooting](troubleshooting.md)
- [Demo gallery](demos.md)
EOF
cat > _Sidebar.md <<'EOF'
- [Home](Home)
- [Getting started](getting-started)
- [Canvas](canvas)
- [Editing](editing)
- [Search](search)
- [Imports](imports)
- [Git](git)
- [Console](console)
- [LSP](lsp)
- [Mods](mods)
- [Settings](settings)
- [Troubleshooting](troubleshooting)
- [Demos](demos)
- [Repository](https://github.com/MiguelCock/yun)
EOF

python3 - "$root" <<'PY'
from pathlib import Path
import re, sys
root = Path(sys.argv[1])
raw = 'https://raw.githubusercontent.com/MiguelCock/yun/main/'
blob = 'https://github.com/MiguelCock/yun/blob/main/'
for page in Path('.').glob('*.md'):
    s = page.read_text()
    s = re.sub(r'\((\.\./screenshots/[^)]+)\)', lambda m: '(' + raw + 'docs/' + m.group(1)[3:] + ')', s)
    s = re.sub(r'\[([^\]]+)\]\((\.\./[^)]+\.md)\)', lambda m: '[' + m.group(1) + '](' + blob + 'docs/' + m.group(2)[3:] + ')', s)
    s = re.sub(r'\[([^\]]+)\]\((?!https?:|#)([^)/]+\.md)\)', lambda m: '[' + m.group(1) + '](' + blob + 'docs/guide/' + m.group(2) + ')', s)
    page.write_text(s)
PY

git add .
if git diff --cached --quiet; then
	echo "Wiki is already up to date."
	exit 0
fi
git -c user.name="Yun docs" -c user.email="docs@yun.invalid" commit -qm "Sync user guide from ${repo}"
git push origin HEAD
echo "Wiki updated: https://github.com/${repo}/wiki"
