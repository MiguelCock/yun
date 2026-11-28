---
name: yun-development
description: Use when writing, reviewing, or refactoring C3 code in Yun, or when touching its architecture, modules, build, tests, or issue backlog. Covers C3 naming/style, allocators, optionals, modules, raylib rendering, tree-sitter highlighting, and Yun's project conventions.
---

# Yun development (C3)

## Non-negotiables
- C3, not C/C++. Verify with `c3c build`; run with `c3c run`; tests `c3c test`; format `c3fmt --in-place <file>` (`--check` to verify). A clean `c3c build` is the bar.
- `project.json` is the single source of build truth. Add libraries as `.c3l` under `lib/` plus a `dependencies` entry.
- Never hand-edit vendored libraries: `lib/raylib6.c3l` is a packed zip; `lib/tree_sitter*.c3l` are directories whose grammar libraries are built (not committed) with `scripts/build-tree-sitter.sh [--static] [target]`; `lib/lua54.c3l` is the vendored Lua 5.4 runtime built with `scripts/build-lua.sh [target]`.
- The `no-unused` warning is on: leave no unused declarations.
- Tabs for indentation. Do not add comments unless asked.
- The roadmap is the flat GitHub issue backlog; work issue by issue and reference `#N`.
- Follow the branch/PR workflow in `CONTRIBUTING.md`: branch `<issue>-<slug>` off `development`, commit `#N ...`, open a PR into `development`. The maintainer reviews and merges every PR; an authorized agent may merge only when the user explicitly asks. After cloning run `git submodule update --init --recursive`.

## C3 conventions (from the bundled manual, 5_7)
- Naming is enforced by the grammar: types `PascalCase`; constants and enum members `SCREAMING_SNAKE_CASE`; functions, macros, variables, and members `snake_case`; modules lowercase (`<=31` chars per sub-path, `<=63` total).
- Style: Allman braces, tabs. Document APIs with `<* ... *>` doc comments and contracts where useful.
- Visibility: use `@private` (module-only) and `@local` (section-only); `import x @public` re-exports internals. Keep internals private by default.
- Zero-initialization is the default; use `@noinit` only when intentional.
- Errors use optionals and faults: `int?`, `!`, `catch`, `if (try ...)`, `faultdef`. Do not discard errors silently.
- Clean up with `defer`, placed immediately after acquiring the resource (files, mmaps).
- Prefer slices over pointers and `foreach` for iteration.
- Allocators: pass an `Allocator`; `mem` for heap, `tmem` for temporaries. Wrap temp usage in `@pool()` and never let temp memory escape the pool or cross threads.
- Stdlib naming: `new` allocates, `temp`/`t` uses the temp allocator, `free`/`destroy`/`close` release (destroy also releases non-memory resources).
- Prefer free functions unless the function acts on a specific type; methods take `self` first.
- Use macros for generics/overloads; keep them simple.
- C interop: `extern fn ... @cname("...")`; use `CInt`/`CChar`/`CLong` at the boundary.
- Concurrency: `std::threads` with channels for producer/consumer work instead of shared mutable state.
- Tests: `@test` functions under `test/**`; `@benchmark` for performance work (#45).

## Yun architecture (current)
- App shell: `src/main.c3` (`module yun;`) owns window/config setup, the frame loop, input routing, overlays, settings application, `run_command`, the draw pass, benchmarks, and the visual suite. Intended future split (not done): `src/app/*.c3` with the same `module yun;`.
- Domain: `yun::project` (project/folder/card model, layout, open flow; `src/project.c3`; intended future `src/project/*.c3`), `yun::canvas`, `yun::card`, `yun::editor`, `yun::text` (`piece_table`, `history`), `yun::workspace`, `yun::recovery`, `yun::spatial`, `yun::index_cache`.
- Code intelligence: `yun::lsp` (`jsonrpc`, `client`, `protocol`, `manager`, `features`, `text`), `yun::completion`, `yun::hover`, `yun::problems`, `yun::symbols`, `yun::find`/`yun::findbar`, `yun::search`.
- Imports/Connections: `yun::imports` (resolution, index, arrows), `yun::connections`, `yun::connection_details`.
- Console/PTY: `yun::console` (`manager`, `console`, `panel`, `buffer`, `input`, `pty`, `runner`, `terminal`).
- Mods: `yun::mods` (sandboxed Lua host). Git: `yun::git` (`model`, `state`, `status`, `diff`, `diff_view`, `history`, `history_view`, `conflict`, `conflict_view`, `branch`, `patch`, `repo`, `executor`, `decorate`, `panel`), `yun::gitignore`.
- UI/commands: `yun::commands`, `yun::keymap`, `yun::context`, `yun::palette`, `yun::menu`, `yun::prompt`, `yun::notify`, `yun::topbar`, `yun::minimap`, `yun::browser`, `yun::settings`, `yun::settings_panel`, `yun::theme`, `yun::skin`, `yun::icons`, `yun::fonts`, `yun::ui`, `yun::vim`, `yun::vim_command`, `yun::version`.
- Implemented, not planned: LSP, Lua mods, and import arrows all ship; see `docs/lsp.md`, `docs/mods.md`, `docs/imports.md`. Focus mode fills the screen with the selected card (`Ctrl+Shift+Enter`); `--visual-suite=<dir>` and `scripts/visual-check.sh` capture deterministic UI screenshots.
- Layering: rendering/UI (raylib) -> commands/app -> domain (canvas, project, cards) -> text/io (piece table, filesystem). Dependencies point inward; no cycles.
- Rendering: raylib snake_case API, draw inside `rl::@drawing() { ... }`; world content via `rl::@mode2d(canvas.camera) { ... }`; screen-space UI after `end_mode2d`; clip editors with `begin_scissor_mode`/`end_scissor_mode`. Binding types: `RLVector2 = float[<2>]`, `RLColor = char[<4>]`, `Rect` comes from `std::math`.
- State ownership: `init`/`destroy` naming, explicit allocators, one owner per resource, avoid global mutable state.
- Text: piece table over a mmap'd original plus an append buffer; edits emit `Edit` records and maintain a line index; never copy the whole file per edit. Undo/redo via `yun::text` history.
- Highlighting: `yun::language` is the registry (enum + `LanguageSpec` table: extensions, library name/symbol, highlights path, import/module/symbols queries); `yun::grammar` lazily loads the grammar shared library (`dlopen`/`LoadLibraryA`). `yun::highlight` looks up the language by extension, lazily builds one `TSQuery` per language from the grammar's `queries/highlights.scm` (searched at CWD, then the executable dir), and keeps a per-card `Highlighter` (parser + tree + sorted `Span`s). The buffer is reparsed whole when dirty; captures map to `SyntaxRole`s and then to a dark palette, kept separate so themes can swap colors without reparsing. Unknown extensions render as plain text.
- Persistence: per-project `.yun/` (workspace, config, mods; ignored by the scanner) plus a global config directory for user settings.
- Background work (project scan, search, LSP reader) runs on worker threads and hands results to the main thread via channels; only the main thread renders.

## Workflow
- Branch model: `main` (release) <- `development` (integration) <- `<issue>-<slug>` features. Full process in `CONTRIBUTING.md`.
- Use the `start-issue` / `finish-issue` opencode commands to branch, verify, commit, push, and open a PR into `development`.
- Stop at the open PR. The maintainer reviews and merges PRs; an authorized agent may merge only when the user explicitly asks. Never push to `main`.
- Start from an issue's acceptance criteria and keep its task checklist updated as you go.
- Make small focused changes; build, test, format, and run the headless smoke test before calling work done. For app/draw/UI changes also run `scripts/visual-check.sh`; for frame/perf work use `c3c run -- --benchmark`.
- Before moving or splitting files read `yun-safe-refactor`; for folder/module layout read `yun-module-organization`; for `src/main.c3`, frame-loop, or overlay work read `yun-app-shell`.
- Add `@test` coverage for pure logic (piece table, config layering, fuzzy matching, JSON-RPC framing).
- Never edit generated/vendored files; document any needed binding change in the issue.
- Reference issue numbers in branches/commits (e.g. `#11 piece table insert`).

## Pitfalls
- `lib/raylib6.c3l` ships prebuilt libs only for linux-x64, macos-aarch64, windows-x64, windows-aarch64, emscripten, wasm-32; there is no linux-aarch64 or macos-x64.
- `lib/tree_sitter*.c3l` grammar shared libraries are built with `scripts/build-tree-sitter.sh [--static] [target]` (other targets need a matching toolchain); they are not committed.
- `lib/lua54.c3l` is a git submodule wired into `project.json` as `lua54`; run `git submodule update --init --recursive` after cloning. Build the runtime with `scripts/build-lua.sh [target]` (the Linux static archive is committed; Windows ships a prebuilt import library/DLL), then load sandboxed mods from the global config directory and `<project>/.yun/mods`.
- `project.json`'s `langrev` is unrelated to the compiler version; `c3c` is external and unpinned (this repo is built with 0.8.4).
- `test/**` holds `@test` coverage (e.g. `test/canvas_test.c3`); grammar libraries must be built before `c3c test`.
- `src/main.c3` and `src/project.c3` are large. Do not split them ad hoc; follow `yun-safe-refactor` and keep behavior-preserving moves separate from features.
- `c3fmt` uses defaults (no repo config).

## C3 gotchas (observed in this repo)
- Functions from other modules must be prefixed (`tree_sitter::ts_query_new`), even when imported. Types and enum members may be used unqualified after `import` (e.g. `TSParser`, `TS_QUERY_ERROR_NONE`), though qualifying them is also fine.
- Use `Type::size` for a type's size (`Span::size`, `Path::size`); `$sizeof` does not exist in 0.8.4.
- Cross-module methods are called on a value (`card.highlight.mark_dirty()`), not as `module::method(value)`.
- Inside a `@test` module every function is a test and may not take parameters; put shared helpers in another module or use a `macro`.
- `List.len()` returns `sz`; comparisons/mixes with `usz` need explicit casts. There is no range `foreach (i : 0..n)` — use a `for` loop.
- `if` with an `else` requires braces. Method names cannot collide with field names. `extern fn` pointer parameters cannot be `const`; alias opaque C types with `typedef X = void;`.
- Only `uint`/`ushort`/`ulong` (no `uint32_t`); `String`/`Path` slices are `[start:len]` (length, not end index); `String` is not null-terminated — use `zstr_tcopy()` in `@pool()` before passing to C APIs.
