---
name: yun-safe-refactor
description: Use when moving or splitting long C3 files in Yun (especially src/main.c3 and src/project.c3) without changing behavior. Covers git mv, whole-function moves, module/import handling, protected regions, verification gates, and reviewable diffs.
---

# Yun safe refactor

## Contract
- Structural PR only: move code, do not change it. No renames, signature changes, formatting sweeps, bug fixes, or features in the same PR. File follow-up issues.
- One cohesive move per PR. If a split needs both a rename and a bug fix, ship the move first.
- Baseline must build, test, and format clean before you start. If `src/main.c3` or `src/project.c3` already has uncommitted parallel edits, stop and coordinate.

## Before moving
- Write down the unit: whole functions or a self-contained block. Record its public surface, callers, module, and the imports it uses.
- Confirm the target module. Safe refactors keep the same declaration (`module yun::project;`, `module yun;`) so symbol names and call sites do not change.
- Choose the target file by responsibility (for example project layout or project file I/O), never "part 2".

## Mechanics
- Whole-file move: `git mv old.c3 new-folder/old.c3`. Directory split: create the target and move whole functions verbatim; use `git mv` where practical.
- Copy the header (`module ...;`) and every import the moved code needs. Remove imports the source no longer uses and add them to the target. C3 imports are file-local.
- Remove the originals from the source file. Duplicate definitions break the build; do not leave stubs, wrappers, or commented-out code.
- Keep function bodies, ordering, and call sites identical. Do not run `c3fmt` on untouched regions or reformat during the move.
- Same module means `@private` helpers keep working across files. Avoid introducing a new module during a safe move because it changes visibility.
- Sibling files never import each other; both repeat the module declaration.

## Do not move yet
These areas encode behavior and ordering; move them only in a dedicated, reviewed change after state ownership is explicit:
- `main()` and its `defer` teardown chain (the LIFO order is deliberate).
- The single `rl::@drawing()` block and the frame phase order.
- Input polling order (`get_mouse_position`, wheel, char input, key presses) and the `Project.update` / `Project.handle_keyboard` event order.
- The `Project` struct and its lifecycle (`init`, `destroy`, `open`, `reset`).
- `App` fields that are stable pointers to long-lived owners; never turn them into per-frame copies.
- The `run_command` dispatch and the overlay `else if` chain until each command/overlay has an extraction plan.

## Verification gates
Run in order after the move:
1. `c3c build` (no warnings; `no-unused` is on)
2. `c3c test`
3. `c3fmt --check $(git ls-files '*.c3')`
4. `c3c run -- --selftest` (window smoke test; grammar libraries must be built)
5. `scripts/visual-check.sh` for app, draw, or UI changes
6. `c3c run -- --benchmark` when frame/update paths moved

If a gate cannot run, say so explicitly instead of implying it passed.

## Reviewable diff
- Exercise the moved unit through the UI or tests before and after when possible.
- `git diff --color-moved=zebra --stat` and `git diff --color-moved` should show moves, not rewrites.
- `git diff --numstat` should be deletion/addition balanced; large asymmetric deltas mean content changed.
- Keep the PR to the move plus import adjustments; commit as `#N <area> split: <file>`.
- Link `yun-module-organization` for folder/module decisions and `yun-app-shell` for `main.c3` constraints.
