# Search, symbols, and connections

![Project-wide search](../screenshots/search.gif)

## Find in the current file

`Ctrl+F` opens the find bar for the focused card. `Ctrl+H` adds replace mode.
Matches update as you type; `Enter` moves to the next match, `Shift+Enter` to the
previous one, and the replace controls stay in the same bar.

## Search the project

`Ctrl+Shift+F` opens project-wide search. `Ctrl+Shift+H` opens it in replace mode.

- Case-sensitive and whole-word toggles are in the search panel.
- Results are grouped by file and show line/column previews.
- `Up`/`Down` select a result; `Enter` opens it at the matching line.
- Replace writes closed matched files immediately. Open files become dirty and
  the change is undoable.
- Limits for file size, matches per file, total results, workers, and debounce
  are configurable under `search`.

## Symbols

`Ctrl+Shift+O` opens the project symbol palette. It indexes functions, types,
constants, and other declarations from tree-sitter and, when available, LSP
document symbols. Type a fuzzy query and press `Enter` to jump.

`F12` requests go-to-definition for the symbol under the caret when an LSP
server is running.

## Connections

`Ctrl+Shift+I` opens the **Connections** panel for the focused card. It lists:

- outgoing imports and the files they resolve to;
- incoming importers;
- imported symbols, aliases, and usage sites when the language supports them;
- external packages that do not resolve inside the project.

Click a row to jump to the import or usage. Hovering an import arrow also fills
the panel; clicking the arrow navigates to its source or target.

External imports are not drawn as arrows. They are shown here because they have
no project card to point at.

## Next

- [Import arrows](imports.md)
