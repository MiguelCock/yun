# tree_sitter_c (C3L)

C grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `tree-sitter/tree-sitter-c`, pinned to `v0.24.2`
- **Language ABI:** 15
- **Module:** `tree_sitter_c`
- **License:** MIT (`LICENSE`)

## Layout

- `tree-sitter-c.c3i` — declares `tree_sitter_c()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/libtree_sitter_c.a` — prebuilt grammar static library (with scanner if the grammar has one).
- `upstream/` — the pinned grammar source (git submodule).

## Building

Prebuilt for `linux-x64`. Regenerate with:

```sh
scripts/build-tree-sitter.sh linux-x64
```

The script compiles `upstream/src/parser.c` and (when present) `upstream/src/scanner.c`
against the runtime headers.
