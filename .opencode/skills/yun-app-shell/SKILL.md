---
name: yun-app-shell
description: Use when changing src/main.c3, the frame loop, startup/teardown, input routing, overlays, settings application, run_command, the render pass, or the selftest/visual-suite/benchmark entry points. Covers ownership, frame phase order, App state, and overlay wiring.
---

# Yun app shell

## Ownership
- `main()` owns window creation/config, startup ordering, the frame loop, argument parsing, and LIFO `defer` teardown. Do not move teardown into helpers with a different ordering.
- `App` holds stable pointers to long-lived owners (project, canvas, config, menus, panels, views). Do not store per-frame values there; keep loop scalars local until a `FrameState`/`AppState` split exists, then put per-frame values in `FrameState` and session state in `AppState`.
- Shared mutable state has one owner. Overlays and views are created in `main()`, pointed to by `App`, destroyed by defers, and closed through `close_overlays`.
- `apply_settings` takes explicit pointers and runs at startup (before `App` exists), every frame, and after a project opens. Keep it safe when project or console data is empty.

## Preserve frame phase order
Current loop order (do not reorder casually):
1. Frame start: cursor reset, refresh console pointers, chrome insets, mode fallbacks, selftest exit, benchmark camera, `dt`, DPI.
2. Sync/pump: search, symbols, git state, diff sync, console manager, console notifications.
3. Settings/recovery: `apply_settings`, mods load/startup dispatch, diagnostics, recovery journal.
4. Open flow: `open_job.step`, `finish_open`, LSP root, import scan, recovery prompt, visual suite start.
5. Overlays (exclusive `else if` chain): browser -> palette -> settings -> problems -> definition menu -> vim command -> name prompt -> close/recovery/delete/reload/theme/profile/context menus -> search -> symbols -> find bar, then workspace.
6. Workspace input/update: edit grace, mouse/world, diff/conflict/history, console panel/manager, git panel, topbar, import hover, `project.update`, follow/layout, focus transitions, mods selection events, imports pump, `canvas.update`.
7. LSP drain: formatting, completion poll, hover, definition, references, rename, code actions, document/workspace symbols, semantic tokens, signature help; then `notifier.update`, `mods.frame`.
8. Draw: exactly one `rl::@drawing()`; background/focus backdrop, `@mode2d` world, screen UI, tooltip, `visual_suite_tick`.
9. Profiling/benchmark sampling; after the loop end focus and save workspace/recovery/caches.

- Overlays call `poll_global` when they did not consume input; keep that pattern so global shortcuts keep working.
- Draw app and editor content inside the existing drawing block; never open a second begin/end pair.

## `run_command` and new features
- `run_command` is a dispatcher: `CommandId` -> handler. Keep command definitions and keymaps in `commands.c3`; put new command families in separate files (for example `src/app/commands_*.c3` with `module yun;`) and call them from the dispatcher.
- Do not grow the switch with feature logic that belongs in a domain module.
- New overlay wiring checklist:
  - Add a stable field to `App` and a local owner in `main()`.
  - Create/init with an allocator; `defer` destroy in the teardown block.
  - Close it in `close_overlays`.
  - Insert it in the exclusive input chain and call `poll_global` when not consumed.
  - Draw it in the drawing block (screen space unless it belongs in the world).
  - Add its command, palette, and context-menu entries.
  - Add or update tests under `test/**` and a visual state.
- New visual states go in `VISUAL_STATE_NAMES` and the expected list in `scripts/visual-check.sh`.

## Entry points and suites
- Keep `--selftest` (exits after a few frames), `--visual-suite=<dir>` (writes deterministic screenshots), `--benchmark`, `--benchmark=N`, and `--benchmark-frames=N` working.
- `scripts/visual-check.sh` builds, creates a fixture project, runs the suite, and asserts every expected PNG.
- App/draw changes need `c3c build`, `c3c test`, `c3fmt --check $(git ls-files '*.c3')`, `c3c run -- --selftest`, and `scripts/visual-check.sh`; perf changes also `--benchmark`.
- For large-file moves follow `yun-safe-refactor`; for new files/folders follow `yun-module-organization`.
