# Yun

![CI](https://github.com/MiguelCock/yun/actions/workflows/ci.yml/badge.svg?branch=development)

Yun is a canvas-based code IDE written in [C3](https://c3-lang.org/) and rendered with **raylib 6**. Instead of tabs, files are movable cards laid out on an infinite pan/zoom canvas, with an embedded editor per card and folder clusters that mirror the project on disk.

The project is early and evolving quickly. The roadmap is the flat GitHub issue backlog: <https://github.com/MiguelCock/yun/issues>.

## Features

- **Canvas** — infinite adaptive grid, drag-to-pan, cursor-anchored zoom, inertial pan, and a minimap overview.
- **Project** — open a folder from the CLI (`c3c run -- <dir>`) or the in-app browser; folder clusters mirror disk folders.
- **Files** — drop files onto the canvas, create new file cards and folders, resize cards, and use right-click context menus.
- **Editor** — a piece-table text buffer with undo/redo, line numbers and gutter, caret navigation and scrolling, UTF-8 input, in-file find (and replace), and external-edit reload.
- **Syntax highlighting** — tree-sitter grammars for C3, C, Python, and JavaScript.
- **App** — top bar actions, command palette, customizable keybindings, notifications, layered config (global + project), and `.yun/workspace.json` persistence.

## Not yet

Import dependency arrows (#24–#27), LSP features (#28–#32), Lua mods (#33–#36), global project search (#38–#40), light/dark themes (#41), large-file/perf work (#14, #45–#47), and release packaging (#48–#49).

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

## License

Yun is released under the [MIT License](LICENSE). In short: use it however you like, but any copy or fork must keep the copyright and license notice.

Vendored libraries and assets keep their own licenses — see the `LICENSE` files inside each `lib/*.c3l`, and `assets/fonts/OFL.txt` for JetBrains Mono.
