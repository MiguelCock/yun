# AGENTS.md

## What this is
- **Yun**: a canvas-based code IDE written in C3, rendering with **raylib 6** (`raylib6::rl`). Files are movable cards on an infinite pan/zoom canvas with embedded editors, import arrows, LSP, and Lua mods.
- The roadmap is the flat GitHub issue backlog: https://github.com/MiguelCock/yun/issues (canvas #1-5, cards/files #6-21, editor/piece-table #11-18, import arrows #24-27, LSP #28-32, Lua mods #33-36, search #37-40, UX #22-23/#41-44, perf/reliability #45-49).
- `src/main.c3` is only a basic-window POC; it does NOT reflect the target architecture.
- For C3 language conventions and Yun's architecture/workflow, follow the `yun-development` skill at `.opencode/skills/yun-development/SKILL.md`.

## Build / verify
- Language is C3 (not C/C++). Uses the external `c3c` (built/tested with 0.8.4); it is NOT pinned in the repo. `project.json`'s `langrev` is unrelated to the compiler version.
- Build: `c3c build` (target `yun`). Run: `c3c run`. Clean: `c3c clean`.
- Test: `c3c test` — `test/**` is wired as `test-sources` (e.g. `test/canvas_test.c3`). Tests use the `@test` attribute.
- Inspect resolved deps/project: `c3c project view`.
- Format: `c3fmt --in-place <file...>` (`--check` to verify only). No repo `.c3fmt` config, so defaults apply.
- No lint/typecheck step; a successful `c3c build` is the verification.

## Layout
- `project.json` is the single source of build truth. The runner depends only on `raylib6` (OpenGL/GLFW bindings were removed).
- `src/**` -> executable target `yun`; `test/**` -> tests; `build/` and `out/` are generated and gitignored.
- `lib/*.c3l` are vendor libraries resolved via `"dependency-search-paths": ["lib"]`.
- `lib/lua54.c3l` is a git submodule; run `git submodule update --init --recursive` after cloning.

## Rendering (raylib6)
- `lib/raylib6.c3l` is a **packed/zipped** library, not a directory. Treat it as an opaque binary blob; don't try to edit files inside it.
- Ships prebuilt static libs for `linux-x64`, `macos-aarch64`, `windows-x64`, `windows-aarch64`, `emscripten`, `wasm-32`; there are NO `linux-aarch64` / `macos-x64` binaries.
- API is raylib snake_case (`rl::init_window`, `rl::close_window`, `rl::window_should_close`), plus a `rl::@drawing() { ... }` block macro that wraps `begin_drawing`/`end_drawing`. raygui is also bundled (`raygui::rg`).

## Lua mods (work in progress)
- `lib/lua54.c3l` is a submodule, vendored but NOT yet in `project.json` dependencies (planned for mods #33-36). It declares the C Lua 5.4 API as `extern ... @cname("lua_*")`, so it needs a linkable Lua library; the Linux linked-lib dirs are empty, so expect link failures on Linux until wired up.

## Workflow
- Branch model: `main` (release) <- `development` (integration) <- `<issue>-<slug>` feature branches. Details in `CONTRIBUTING.md`.
- Commit with the issue prefix (`#1 ...`), push, and open a PR into `development`. **Never merge a PR** — the maintainer reviews every PR and merges it (squash) themselves.
- opencode commands: `start-issue` (branch off `development`) and `finish-issue` (verify, commit, push, open PR).
- CI (`.github/workflows/ci.yml`) runs `c3c build`, `c3c test`, and `c3fmt --check` on PRs.

## Conventions
- `project.json` enables the `no-unused` warning; keep code free of unused declarations.
- Match existing `src/main.c3` style (tab indentation). Do not add comments unless asked.
