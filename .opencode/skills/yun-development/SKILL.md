---
name: yun-development
description: Use when writing, reviewing, or refactoring C3 code in Yun, or when touching its architecture, modules, build, tests, or issue backlog. Covers C3 naming/style, allocators, optionals, modules, raylib rendering, and Yun's project conventions.
---

# Yun development (C3)

## Non-negotiables
- C3, not C/C++. Verify with `c3c build`; run with `c3c run`; tests `c3c test`; format `c3fmt --in-place <file>` (`--check` to verify). A clean `c3c build` is the bar.
- `project.json` is the single source of build truth. Add libraries as `.c3l` under `lib/` plus a `dependencies` entry.
- Never hand-edit vendored libraries: `lib/raylib6.c3l` is a packed zip; `lib/lua54.c3l` is a binding that links a system Lua 5.4.
- The `no-unused` warning is on: leave no unused declarations.
- Tabs for indentation. Do not add comments unless asked.
- The roadmap is the flat GitHub issue backlog; work issue by issue and reference `#N`.
- Follow the branch/PR workflow in `CONTRIBUTING.md`: branch `<issue>-<slug>` off `development`, commit `#N ...`, open a PR into `development`. **Never merge a PR** — the maintainer reviews every PR before merging. After cloning run `git submodule update --init --recursive`.

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

## Yun architecture (target)
- Planned modules: `yun::canvas`, `yun::project`, `yun::card`, `yun::text`, `yun::commands`, `yun::config`, `yun::theme`, `yun::lsp`, `yun::mods`. `src/main.c3` is only a raylib POC today; do not treat it as the architecture.
- Layering: rendering/UI (raylib) -> commands/app -> domain (canvas, project, cards) -> text/io (piece table, filesystem). Dependencies point inward; no cycles.
- Rendering: raylib snake_case API, draw inside `rl::@drawing() { ... }`; world content via `rl::@mode2d(canvas.camera) { ... }`; screen-space UI after `end_mode2d`; clip editors with `begin_scissor_mode`/`end_scissor_mode`. Binding types: `RLVector2 = float[<2>]`, `RLColor = char[<4>]`, `Rect` comes from `std::math`.
- State ownership: `init`/`destroy` naming, explicit allocators, one owner per resource, avoid global mutable state.
- Text: piece table over a mmap'd original plus an append buffer; emit edit records; never copy the whole file per edit.
- Persistence: per-project `.yun/` (workspace, config, mods; ignored by the scanner) plus a global config directory for user settings.
- Background work (project scan, search, LSP reader) runs on worker threads and hands results to the main thread via channels; only the main thread renders.

## Workflow
- Branch model: `main` (release) <- `development` (integration) <- `<issue>-<slug>` features. Full process in `CONTRIBUTING.md`.
- Use the `start-issue` / `finish-issue` opencode commands to branch, verify, commit, push, and open a PR into `development`.
- Stop at the open PR. Never merge, squash, or close a PR (or push to `main`); leave it for the maintainer to review and merge.
- Start from an issue's acceptance criteria and keep its task checklist updated as you go.
- Make small focused changes; build, test, and `c3fmt --check` before calling work done.
- Add `@test` coverage for pure logic (piece table, config layering, fuzzy matching, JSON-RPC framing).
- Never edit generated/vendored files; document any needed binding change in the issue.
- Reference issue numbers in branches/commits (e.g. `#11 piece table insert`).

## Pitfalls
- `lib/raylib6.c3l` ships prebuilt libs only for linux-x64, macos-aarch64, windows-x64, windows-aarch64, emscripten, wasm-32; there is no linux-aarch64 or macos-x64.
- `lib/lua54.c3l` is a git submodule; run `git submodule update --init --recursive` after cloning. It declares C Lua via `@cname("lua_*")` and currently links only on windows-x64; Linux needs a system Lua 5.4 (e.g. `liblua5.4-dev`) wired into its manifest.
- `project.json`'s `langrev` is unrelated to the compiler version; `c3c` is external and unpinned (this repo is built with 0.8.4).
- `test/**` holds `@test` coverage (e.g. `test/canvas_test.c3`).
- `c3fmt` uses defaults (no repo config).
