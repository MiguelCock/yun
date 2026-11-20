# Markdown preview

Markdown files (`.md`, `.markdown`) get tree-sitter highlighting like any other
language (block grammar + the injected `markdown_inline` grammar), and a card can
additionally show a **rendered preview**.

## Toggling

Three ways to toggle the preview for a Markdown card:

- **Keybind**: `Ctrl+Shift+V` (rebindable via the `toggle_preview` command).
- **Command palette**: "Toggle Preview".
- **Card title**: the preview icon on the right of the title bar (drawn in the
  focus color and on a hover background while the preview is on).

The preview is off by default. It is only available for Markdown cards.

## Interaction

- The wheel scrolls the preview independently of the source scroll position.
- **Clicking the preview returns to the source editor** and places the caret at
  the start of the block you clicked.
- Card resize and the editor font size both reflow the preview.

## What is rendered

- ATX headings (`#`..`######`), scaled up and bold.
- Paragraphs (word-wrapped), unordered and ordered lists (indented, with
  bullets/numbers), single-level blockquotes (bar + indent), thematic breaks.
- GitHub-flavored tables with a header row, alignment (`:---`, `:--:`, `---:`),
  column separators, a header background/underline, and wrapped cells. Cell text
  supports the inline styles below, and escaped pipes (`\|`) stay in one cell.
- Fenced code blocks (no wrapping) on a code background; the fence body is
  syntax-highlighted by reusing the block highlighter's injected spans when the
  fence language is supported, otherwise drawn in the code color.
- Inline `**strong**`/`__strong__` (bold), `*em*`/`_em_` (accent color),
  `` `code` `` (code color), and `[text](url)` (link color + underline).

## Out of scope (v1)

Setext headings (`Title\n=====`), nested blockquotes (`> >`), images, math,
HTML passthrough, and true italic/bold font faces (the bundled font is
JetBrains Mono Regular, so bold is drawn twice with a 1px offset).

## Persistence

The per-card preview flag is stored in `.yun/workspace.json`. The workspace
version was bumped (`1` -> `2`) for this field, so an existing `.yun` folder is
discarded once on first load; delete `.yun` and reopen the project to start
fresh.
