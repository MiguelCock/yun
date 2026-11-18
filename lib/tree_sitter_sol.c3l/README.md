# tree_sitter_sol (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Source:** vendored snapshot of `tree-sitter-sol` from the private SOL
  repository at `37feb74`
- **Language ABI:** 14
- **Module:** `tree_sitter_sol`
- **License:** see `LICENSE`

## Why vendored

Yun is public and the SOL repository is private, so a git submodule cannot be
cloned by CI or by users. This directory vendors the generated parser and the
canonical queries instead. The SOL repository remains the source of truth.

## Layout

- `tree-sitter-sol.c3i` — declares `tree_sitter_sol()` returning the `TSLanguage*`.
- `queries/` — vendored SOL queries.
- `upstream/tree-sitter-sol/` — vendored `grammar.js`, `src/parser.c`, headers, and license.
- `linked-libs/<target>/` — built grammar library.
- `grammar.conf` — build options (`src`/`queries`/`lib`) read by Yun.

## Updating

Copy `tree-sitter-sol/src`, `tree-sitter-sol/grammar.js`,
`tree-sitter-sol/LICENSE`, and the canonical `queries/sol/*.scm` files from the
SOL repository, then rebuild and run `c3c test`.

## Building

```sh
scripts/build-tree-sitter.sh linux-x64 sol
```
