# tree_sitter_sol (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/MiguelCock/sol.git`, pinned to `37feb74`
- **Language ABI:** 14
- **Module:** `tree_sitter_sol`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-sol.c3i` — declares `tree_sitter_sol()` returning the `TSLanguage*`.
- `queries/` — vendored SOL queries; the canonical sources live in
  `upstream/queries/sol/`.
- `linked-libs/<target>/` — built grammar library.
- `grammar.conf` — build options (`src`/`queries`/`lib`) read by Yun.
- `upstream/` — the pinned SOL repository (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh linux-x64 sol
```
