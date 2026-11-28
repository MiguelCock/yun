# AGENTS.md

## What this is
- **Yun**: a canvas-based code IDE written in C3, rendering with **raylib 6** (`raylib6::rl`). Files are movable cards on an infinite pan/zoom canvas with embedded editors and tree-sitter syntax highlighting. Import arrows, LSP code intelligence, sandboxed Lua mods, Connections, the command console/PTY, focus mode, and a visual screenshot suite are implemented.
- The roadmap is the flat GitHub issue backlog: https://github.com/MiguelCock/yun/issues (canvas, cards/files, editor/highlighting, import arrows, LSP, mods, search, UX, perf/reliability). Many items are shipped; use the issue state, not this list, as the source of truth.
- `src/main.c3` is the app shell (window setup, frame loop, input routing, menus, overlays); `src/project.c3` is the project/card domain. The rest of the architecture lives in the `src/**` modules.
- Repo skills: `yun-development` (C3 conventions, architecture, workflow), `yun-module-organization` (adding/moving/splitting files), `yun-safe-refactor` (behavior-preserving moves of long files), and `yun-app-shell` (main.c3, frame loop, overlays, suites). All live under `.opencode/skills/`.

## Implemented features
- **LSP** (`src/lsp/`, `docs/lsp.md`): hover, definition, completion, diagnostics, document/workspace symbols, references, rename, code actions, signature help, semantic tokens, and inlay hints; each server feature is optional.
- **Imports and Connections** (`src/imports.c3`, `src/connections.c3`, `docs/imports.md`): language-aware resolution, orthogonal arrows between cards, and external imports listed in Connections.
- **Console/PTY** (`src/console/`, `docs/guide/console.md`): command runner, ANSI output, history/completion, sessions, run profiles, and an optional persistent PTY.
- **Mods** (`src/mods.c3`, `docs/mods.md`): sandboxed Lua 5.4 with lifecycle events, palette/context commands, notifications, and optional render/input overlays.
- **Focus mode and visual suite**: `Ctrl+Shift+Enter` focuses a card; `--visual-suite=<dir>` plus `scripts/visual-check.sh` captures deterministic screenshots.

## Build / verify
- Language is C3 (not C/C++). Uses the external `c3c` (built/tested with 0.8.4); it is NOT pinned in the repo. `project.json`'s `langrev` is unrelated to the compiler version.
- Build: `c3c build` (target `yun`). Run: `c3c run` (optionally `c3c run -- <dir>`). Clean: `c3c clean`.
- Test: `c3c test` — `test/**` is wired as `test-sources` (e.g. `test/canvas_test.c3`). Tests use the `@test` attribute. Grammar libraries are loaded lazily, so run `scripts/build-tree-sitter.sh linux-x64` once after cloning before `c3c test`.
- Inspect resolved deps/project: `c3c project view`.
- Format: `c3fmt --in-place <file...>` (`--check` to verify only). No repo `.c3fmt` config, so defaults apply.
- No lint/typecheck step; a successful build plus tests and the format check is the verification.
- `third_party/yun_stb_image.c` is the one C source, compiled by `c3c` through `c-sources`; it provides the JPEG decoder that the bundled raylib build lacks.

## Layout
- `project.json` is the single source of build truth. Dependencies are `raylib6`, `tree_sitter`, and `lua54`; grammars are loaded lazily from shared libraries (built with `scripts/build-tree-sitter.sh`, not committed).
- `src/**` -> executable target `yun`; `test/**` -> tests; `build/` and `out/` are generated and gitignored. New folders under either tree are picked up automatically.
- Domain folders use one C3 module per folder: `src/console/*.c3` -> `yun::console`, `src/git/*.c3` -> `yun::git`, `src/lsp/*.c3` -> `yun::lsp`, `src/text/*.c3` -> `yun::text`. Other top-level `src/*.c3` files are single-module domains (e.g. `yun::canvas`, `yun::imports`, `yun::mods`); `src/main.c3` is `module yun;` (see `yun-app-shell`). New files follow `yun-module-organization`.
- `src/project/` is now the project domain folder: `project.c3` (model/lifecycle), `paths.c3`, and `clusters.c3` (all `module yun::project;`). Further behavior-preserving splits (`layout.c3`, `open_job.c3`, `draw.c3`, `cards.c3`, `selection.c3`, `focus.c3`, `pointer.c3`, `update.c3`) are planned; do not assume they exist yet. `src/main.c3` remains `module yun;`; an `src/app/` helper split is also planned. See `yun-safe-refactor` and `yun-module-organization`.
- `lib/*.c3l` are vendor libraries resolved via `"dependency-search-paths": ["lib"]`.
- `src/image.c3` (`yun::image`) is the shared still-image loader and supported-extension registry. `third_party/` holds vendored C sources and their licenses.
- `assets/fonts/` ships JetBrains Mono (SIL OFL 1.1) plus its license.
- `lib/lua54.c3l` and the tree-sitter `upstream/` sources are git submodules; run `git submodule update --init --recursive` after cloning. The Lua 5.4 runtime is built with `scripts/build-lua.sh` (the Linux archive is committed; Windows ships a prebuilt DLL).

## Rendering (raylib6)
- `lib/raylib6.c3l` is a **packed/zipped** library, not a directory. Treat it as an opaque binary blob; don't try to edit files inside it.
- Ships prebuilt static libs for `linux-x64`, `macos-aarch64`, `windows-x64`, `windows-aarch64`, `emscripten`, `wasm-32`; there are NO `linux-aarch64` / `macos-x64` binaries.
- API is raylib snake_case (`rl::init_window`, `rl::close_window`, `rl::window_should_close`), plus a `rl::@drawing() { ... }` block macro that wraps `begin_drawing`/`end_drawing`. raygui is also bundled (`raygui::rg`).
- Skin images render over an opaque surface base; `skin.image_scope` defaults to `selected` so card/folder wallpapers only render on the selection unless set to `all`.
- The bundled raylib static libs are compiled without JPEG decoding. Use `yun::image` when loading still images; it falls back to the vendored stb JPEG decoder. GIF playback still goes through raylib.

## Syntax highlighting (tree-sitter)
- `src/language.c3` (`yun::language`) is the language registry: the `Language` enum plus a `LanguageSpec` table (name, extensions, library name/symbol, highlights/injections paths, import/module/symbols queries) and a `language_for_name` resolver. Adding a language is one table entry plus its grammar library.
- `src/highlight.c3` (`yun::highlight`) uses the registry for lazy per-language `TSQuery` caches loaded from each grammar's `queries/highlights.scm` and `queries/injections.scm`, and a per-card `Highlighter` (parser + tree + sorted `Span`s) that reparses the whole buffer when dirty. The injection engine re-parses `@injection.content` regions with another grammar (static/dynamic language, `combined`, `#eq?` predicates, depth-limited).
- `src/grammar.c3` (`yun::grammar`) lazily loads grammar shared libraries (`dlopen`/`LoadLibraryA`) with a fallback to plain text when missing.
- `lib/tree_sitter*.c3l` are directories (not packed); their `upstream/` dirs are submodules. Build grammar libraries with `scripts/build-tree-sitter.sh [--static] [target] [grammar...]`. See `docs/tree-sitter.md` for the grammar pipeline (scaffold, build, ABI, licenses).
- `lib/tree_sitter.c3l/tree-sitter.c3i` is a hand-maintained runtime binding tracked directly in this repo (only `upstream/` is a submodule); extend it when the runtime API is needed.
- Capture names map to `SyntaxRole`s and then to a dark palette in the same module, kept separate so themes can swap colors without reparsing.

## Lua runtime
- `lib/lua54.c3l` is a submodule wired into `project.json` as `lua54`. Build it with `scripts/build-lua.sh [target]`; the Linux static archive is committed and Windows ships a prebuilt import library/DLL.
- Mods are sandboxed Lua 5.4 scripts loaded from the global config directory and `<project>/.yun/mods`; render/input permissions are off by default. See `docs/mods.md`.

## Workflow
- Branch model: `main` (release) <- `development` (integration) <- `<issue>-<slug>` feature branches. Details in `CONTRIBUTING.md`.
- Commit with the issue prefix (`#1 ...`), push, and open a PR into `development`. The maintainer reviews and merges PRs (squash); an authorized agent may also merge when the user explicitly asks.
- opencode commands: `start-issue` (branch off `development`) and `finish-issue` (verify, commit, push, open PR).
- CI (`.github/workflows/ci.yml`) runs `c3c build`, `c3c test`, and `c3fmt --check` on PRs.
- Local verification: `c3c build`, `c3c test`, `c3fmt --check $(git ls-files '*.c3')`, and `c3c run -- --selftest`. For app/draw/UI changes also run `scripts/visual-check.sh`; for frame/perf work run `c3c run -- --benchmark`.
- Skill routing: `yun-module-organization` for new files/folders, `yun-safe-refactor` before moving long files, and `yun-app-shell` for `src/main.c3`, frame-loop, or overlay work.

## Conventions
- `project.json` enables the `no-unused` warning; keep code free of unused declarations.
- Match existing `src/**` style (tab indentation). Do not add comments unless asked.

## License
- MIT (see `LICENSE`): use freely, but any copy or fork must retain the copyright and license notice. Vendored libraries and assets keep their own licenses. `third_party/stb_image.h` is public domain / MIT.
