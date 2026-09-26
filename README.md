# Yun

![CI](https://github.com/MiguelCock/yun/actions/workflows/ci.yml/badge.svg?branch=development)

Yun is a canvas-based code IDE written in [C3](https://c3-lang.org/) and rendered with **raylib 6**. Instead of tabs, files are movable cards laid out on an infinite pan/zoom canvas, with an embedded editor per card and folder clusters that mirror the project on disk.

The project is early and evolving quickly. The roadmap is the flat GitHub issue backlog: <https://github.com/MiguelCock/yun/issues>.

## Features

- **Canvas** — infinite adaptive grid, drag-to-pan, cursor-anchored zoom, inertial pan, and a minimap overview.
- **Project** — open a folder from the CLI (`c3c run -- <dir>`) or the in-app browser; folder clusters mirror disk folders.
- **Files** — drop files onto the canvas, create new file cards and folders, resize cards, and use right-click context menus.
- **Editor** — a piece-table text buffer with undo/redo, line numbers and gutter, caret navigation and scrolling, UTF-8 input, in-file find (and replace), adjustable font size, and external-edit reload.
- **Syntax highlighting** — tree-sitter grammars for C3, C, Python, and JavaScript.
- **Search** — in-file find/replace, project-wide search, and a fuzzy symbol palette.
- **Dependencies** — import arrows between cards, with animated, line-highlighted jumps to results, definitions, and symbols.
- **LSP** — hover, go-to-definition, completion, and a problems panel, driven by per-language servers configured in the config.
- **Themes** — nine built-in palettes with a picker.
- **App** — top bar actions, Vim-like keyboard modes (see [Keyboard and modes](#keyboard-and-modes)), command palette, customizable keybindings, notifications, layered config (global + project), and `.yun/workspace.json` persistence.

## Not yet

Lua mods (#33–#36), large-file support (#14), very-large-project perf (#45), crash recovery (#47), HiDPI scaling (#44), and release packaging (#48–#49).

## Keyboard and modes

Yun is keyboard-first and Vim-inspired. There are three modes, shown by an indicator next to the FPS counter (`-- MOVE --`, `-- EDIT --`, `-- TOP BAR --`). Overlays (command palette, search, symbol palette, problems panel, find bar, menus, prompts) are modal and handle their own keys.

### MOVE (default)

The cursor is a card on the canvas; no text is being edited.

| Key | Action |
| --- | --- |
| `h` `j` `k` `l` / arrow keys | Move the cursor to the nearest card left / down / up / right |
| `[` / `]` | Previous / next card (wraps) |
| `Shift` + `h` `j` `k` `l` | Pan the canvas |
| `=` / `+` / keypad `+` | Zoom in |
| `-` / keypad `-` | Zoom out |
| `Enter` or `i` | Edit the selected card (enter EDIT) |
| `Tab` | Focus the top bar (enter TOP BAR) |

Mouse panning, zooming, clicking and dragging still work as before.

### EDIT

Typing edits the focused card; arrow keys move the caret, `Tab` indents, and the usual editing shortcuts apply. `Esc` returns to MOVE and keeps the card selected, so you can keep browsing with `[` / `]`.

### TOP BAR

`Left` / `Right` move between buttons (disabled ones are skipped), `Enter` / `Space` activate the selected one, and `Tab` or `Esc` return to MOVE. The focused button is outlined.

### Global shortcuts

These work from any mode:

| Key | Action |
| --- | --- |
| `Ctrl+Shift+P` | Command palette |
| `Ctrl+F` / `Ctrl+H` | Find / replace in the focused file |
| `Ctrl+Shift+F` | Search in project |
| `Ctrl+Shift+O` | Go to symbol |
| `F12` | Go to definition |
| `Ctrl+Shift+M` | Problems panel |
| `Ctrl+Shift+T` | Theme picker |
| `Ctrl+N` / `Ctrl+O` / `Ctrl+S` | New / open / save |
| `Ctrl+Z` / `Ctrl+Y` | Undo / redo |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` / `Ctrl+A` | Copy / cut / paste / select all |
| `Ctrl+Space` | Trigger completion |
| `Ctrl` + scroll | Editor font size |
| `F3` (hold) | Show the awake/asleep editor counter |

Bindings are customizable via the `keymap` object in the config — global `~/.config/yun/config.json` or project `<root>/.yun/config.json` — e.g. `{ "keymap": { "save": "Ctrl+K" } }`.

## Getting started

Requires the external `c3c` compiler (built/tested with 0.8.4). On Linux, install the native dependencies listed in [`.github/workflows/ci.yml`](.github/workflows/ci.yml): `libx11-dev libxrandr-dev libxinerama-dev libxi-dev libxcursor-dev libgl1-mesa-dev`.

```sh
git clone --recurse-submodules https://github.com/MiguelCock/yun.git
cd yun

c3c build                 # build the `yun` executable
c3c run                   # run
c3c run -- <directory>    # run and open a project folder
c3c test                  # run the test suite
c3fmt --check $(git ls-files '*.c3')   # formatting check
```

Already cloned without submodules? Run `git submodule update --init --recursive`.

## Dependencies

- **raylib 6** — `lib/raylib6.c3l` is a packed library; it ships prebuilt static libs for `linux-x64`, `macos-aarch64`, `windows-x64`, `windows-aarch64`, `emscripten`, and `wasm-32`.
- **tree-sitter** — `lib/tree_sitter.c3l` (runtime) plus the `tree_sitter_c`, `tree_sitter_c3`, `tree_sitter_python`, and `tree_sitter_javascript` grammars. `linux-x64` static libraries are committed; regenerate them (or build another target with a matching toolchain) with `scripts/build-tree-sitter.sh <target>`.
- **Lua 5.4** — `lib/lua54.c3l` is a submodule vendored ahead of the mods work (#33–#36); it is not wired into the build yet.

## Layout

```
src/**      executable target `yun`
test/**     `@test` suite
lib/*.c3l   vendored libraries
assets/     bundled fonts (JetBrains Mono, SIL OFL 1.1)
```

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the branch/PR workflow, [`AGENTS.md`](AGENTS.md) for the build/architecture cheat sheet, and [`.opencode/skills/yun-development/SKILL.md`](.opencode/skills/yun-development/SKILL.md) for C3 conventions.

## Configuration

Settings are JSON, layered as `defaults < global < project`, so a project can override your global preferences:

- Global: `<OS config dir>/yun/config.json` (e.g. `~/.config/yun/config.json` on Linux).
- Project: `.yun/config.json` at the project root (wins over global).

Values are grouped into sections, for example:

```json
{
  "app": { "theme": "dark" },
  "editor": { "font_size": 16 },
  "keymap": { "save": "Ctrl+S" },
  "lsp": { "c3": "c3lsp" }
}
```

Unknown top-level keys or section keys warn and are ignored, and a missing config is valid (built-in defaults apply).

In the editor, open the **Settings** panel with `Ctrl+Shift+S`, the top bar's *Settings* button, or the command palette. Changes apply live; `Tab` switches between the global and project scopes and `Del` resets the selected value.

## Versioning and releases

Yun is **pre-1.0**: versions are `0.<MINOR>.0`, where `MINOR` is the cumulative number of closed issues at release time (it only ever increases), and `PATCH` stays `0`. Once the API and UX are stable we will move to [semantic versioning](https://semver.org/). The version lives in [`project.json`](project.json) (and `yun::version.APP_VERSION`, kept in sync by a test).

Releases are built and published by [`.github/workflows/release.yml`](.github/workflows/release.yml). **Merging a PR never publishes anything** — the workflow only builds. To cut a release, set the version to `0.<closed-issues>.0` and push a matching tag:

```sh
git tag v0.44.0
git push origin v0.44.0
```

Tagging builds `linux-x64`, `macos-aarch64`, and `windows-x64` and attaches the archives (with SHA-256 checksums) to the GitHub Release. The tag must equal `v<version from project.json>`, otherwise publishing is aborted.

## License

Yun is released under the [MIT License](LICENSE). In short: use it however you like, but any copy or fork must keep the copyright and license notice.

Vendored libraries and assets keep their own licenses — see the `LICENSE` files inside each `lib/*.c3l`, and `assets/fonts/OFL.txt` for JetBrains Mono.
