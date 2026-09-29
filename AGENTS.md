# AGENTS.md

## What this is
- **Yun**: a canvas-based code IDE written in C3, rendering with **raylib 6** (`raylib6::rl`). Files are movable cards on an infinite pan/zoom canvas with embedded editors and tree-sitter syntax highlighting. Import arrows, LSP, and Lua mods are planned, not implemented.
- The roadmap is the flat GitHub issue backlog: https://github.com/MiguelCock/yun/issues (canvas #1-5, cards/files #6-21, editor/highlighting #11-18/#16, import arrows #24-27, LSP #28-32, Lua mods #33-36, search #37-40, UX #22-23/#41-44, perf/reliability #45-49).
- `src/main.c3` is the app entry point (window setup, frame loop, input routing, menu wiring); the architecture lives in the `src/**` modules.
- For C3 language conventions and Yun's architecture/workflow, follow the `yun-development` skill at `.opencode/skills/yun-development/SKILL.md`.

## Build / verify
- Language is C3 (not C/C++). Uses the external `c3c` (built/tested with 0.8.4); it is NOT pinned in the repo. `project.json`'s `langrev` is unrelated to the compiler version.
- Build: `c3c build` (target `yun`). Run: `c3c run` (optionally `c3c run -- <dir>`). Clean: `c3c clean`.
- Test: `c3c test` — `test/**` is wired as `test-sources` (e.g. `test/canvas_test.c3`). Tests use the `@test` attribute. Grammar libraries are loaded lazily, so run `scripts/build-tree-sitter.sh linux-x64` once after cloning before `c3c test`.
- Inspect resolved deps/project: `c3c project view`.
- Format: `c3fmt --in-place <file...>` (`--check` to verify only). No repo `.c3fmt` config, so defaults apply.
- No lint/typecheck step; a successful `c3c build` is the verification.

## Layout
- `project.json` is the single source of build truth. Dependencies are `raylib6` plus the tree-sitter runtime; grammars are loaded lazily from shared libraries (built with `scripts/build-tree-sitter.sh`, not committed).
- `src/**` -> executable target `yun`; `test/**` -> tests; `build/` and `out/` are generated and gitignored.
- `src/text/` holds the text engine (`piece_table.c3`, `history.c3`); other `src/*.c3` files are the app/UI modules.
- `lib/*.c3l` are vendor libraries resolved via `"dependency-search-paths": ["lib"]`.
- `assets/fonts/` ships JetBrains Mono (SIL OFL 1.1) plus its license.
- `lib/lua54.c3l` and the tree-sitter `upstream/` sources are git submodules; run `git submodule update --init --recursive` after cloning.

## Rendering (raylib6)
- `lib/raylib6.c3l` is a **packed/zipped** library, not a directory. Treat it as an opaque binary blob; don't try to edit files inside it.
- Ships prebuilt static libs for `linux-x64`, `macos-aarch64`, `windows-x64`, `windows-aarch64`, `emscripten`, `wasm-32`; there are NO `linux-aarch64` / `macos-x64` binaries.
- API is raylib snake_case (`rl::init_window`, `rl::close_window`, `rl::window_should_close`), plus a `rl::@drawing() { ... }` block macro that wraps `begin_drawing`/`end_drawing`. raygui is also bundled (`raygui::rg`).

## Syntax highlighting (tree-sitter)
- `src/language.c3` (`yun::language`) is the language registry: the `Language` enum plus a `LanguageSpec` table (name, extensions, library name/symbol, highlights/injections paths, import/module/symbols queries) and a `language_for_name` resolver. Adding a language is one table entry plus its grammar library.
- `src/highlight.c3` (`yun::highlight`) uses the registry for lazy per-language `TSQuery` caches loaded from each grammar's `queries/highlights.scm` and `queries/injections.scm`, and a per-card `Highlighter` (parser + tree + sorted `Span`s) that reparses the whole buffer when dirty. The injection engine re-parses `@injection.content` regions with another grammar (static/dynamic language, `combined`, `#eq?` predicates, depth-limited).
- `src/grammar.c3` (`yun::grammar`) lazily loads grammar shared libraries (`dlopen`/`LoadLibraryA`) with a fallback to plain text when missing.
- `lib/tree_sitter*.c3l` are directories (not packed); their `upstream/` dirs are submodules. Build grammar libraries with `scripts/build-tree-sitter.sh [--static] [target] [grammar...]`. See `docs/tree-sitter.md` for the grammar pipeline (scaffold, build, ABI, licenses).
- `lib/tree_sitter.c3l/tree-sitter.c3i` is a hand-maintained runtime binding tracked directly in this repo (only `upstream/` is a submodule); extend it when the runtime API is needed.
- Capture names map to `SyntaxRole`s and then to a dark palette in the same module, kept separate so the theme work (#41) can swap colors without reparsing.

## Lua mods (planned)
- `lib/lua54.c3l` is a submodule, vendored but NOT yet in `project.json` dependencies (planned for mods #33-36). It declares the C Lua 5.4 API as `extern ... @cname("lua_*")`, so it needs a linkable Lua library; the Linux linked-lib dirs are empty, so expect link failures on Linux until wired up.

## Workflow
- Branch model: `main` (release) <- `development` (integration) <- `<issue>-<slug>` feature branches. Details in `CONTRIBUTING.md`.
- Commit with the issue prefix (`#1 ...`), push, and open a PR into `development`. **Never merge a PR** — the maintainer reviews every PR and merges it (squash) themselves.
- opencode commands: `start-issue` (branch off `development`) and `finish-issue` (verify, commit, push, open PR).
- CI (`.github/workflows/ci.yml`) runs `c3c build`, `c3c test`, and `c3fmt --check` on PRs.

## Conventions
- `project.json` enables the `no-unused` warning; keep code free of unused declarations.
- Match existing `src/**` style (tab indentation). Do not add comments unless asked.

## License
- MIT (see `LICENSE`): use freely, but any copy or fork must retain the copyright and license notice. Vendored libraries and assets keep their own licenses.
