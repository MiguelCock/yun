---
name: yun-module-organization
description: Use when adding, moving, splitting, or naming C3 files in Yun, choosing folder/module boundaries, fixing imports, or adding tests. Covers one-module-per-domain folders, per-file imports, private/test access, file sizing, and when a new submodule is justified.
---

# Yun module organization

## Ground truth first
- `project.json` sources `src/**` and `test/**`; a new folder under either tree needs no manifest change.
- Check actual module names with `grep -rn '^module ' src test` before inventing a folder.
- Existing domain folders set the pattern: `src/console/*.c3` -> `module yun::console;`, `src/git/*.c3` -> `yun::git`, `src/lsp/*.c3` -> `yun::lsp`, `src/text/*.c3` -> `yun::text`. `src/main.c3` is `module yun;`.
- Intended future split (not done): `src/project/*.c3` -> `module yun::project;` (currently `src/project.c3`) and `src/app/*.c3` -> `module yun;` (currently `src/main.c3`). Do not create empty folders or claim the split is complete.

## Folder and module rules
- One module per domain folder. Every `.c3` file in a folder repeats the same module declaration; the folder is the namespace.
- File names describe responsibility (`layout.c3`, `open.c3`, `keyboard.c3`), not sequence or layer.
- One new file should hold one cohesive responsibility. Split at natural seams (model vs layout vs I/O vs draw vs keyboard), not at arbitrary line counts.
- Target roughly 200-500 lines per new file. Existing 1k+ files are legacy to shrink over time, not templates.
- Sibling files in the same module do not import each other. The shared module declaration is the visibility boundary.
- No module self-imports: never `import yun::project` inside `src/project/**`, or `import yun;` inside `src/app/**`.
- Imports are per-file in C3. Each file imports the modules its own code calls; copy imports with moved code and drop imports the file no longer uses.
- Keep layering: UI/rendering -> app/commands -> domain -> text/IO. Dependencies point inward; no cycles.

## Same-module splits and visibility
- Splitting inside the existing module preserves `@private` helpers and test access.
- Tests stay under `test/**` and declare the production module, e.g. `module yun::project @test;`; they can reach `@private` members of the same module.
- A new module ends that access: `@private` helpers are no longer reachable from the old module or its tests. Expose the deliberate API with `@public`, or keep the split in the same module.
- Do not widen visibility just to dodge a layout decision.

## When a new submodule is justified
Create a new module only when all of these hold:
1. It owns state, a lifecycle, or a resource distinct from the current module.
2. It presents a small, intentional public API.
3. Keeping it in the current module would drag unrelated imports across the boundary.
4. It matches an existing domain pattern (console, git, lsp, text).

Do not create a module merely to shorten a file, hide a helper, or avoid learning the current module. Prefer a same-module file split first.

## Tests and style
- One test file per area under `test/**`; helper modules must omit `@test` because every function in a `@test` module is a parameterless test.
- Tabs, Allman braces, no comments unless asked; C3 enforces naming; leave no unused declarations.
- Verify with `c3c build`, `c3c test`, and `c3fmt --check $(git ls-files '*.c3')`.
- Read `yun-development` for C3 language details and `yun-safe-refactor` before moving existing code.
