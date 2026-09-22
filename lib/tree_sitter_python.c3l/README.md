# tree_sitter_python (C3L)

Python grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `tree-sitter/tree-sitter-python`, pinned to `v0.25.0`
- **Language ABI:** 15
- **Module:** `tree_sitter_python`
- **License:** MIT (`LICENSE`)

## Layout

- `tree-sitter-python.c3i` — declares `tree_sitter_python()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/libtree_sitter_python.a` — prebuilt grammar static library (with scanner if the grammar has one).
- `upstream/` — the pinned grammar source (git submodule).

## Building

Prebuilt for `linux-x64`. Regenerate with:

```sh
scripts/build-tree-sitter.sh linux-x64
```

The script compiles `upstream/src/parser.c` and (when present) `upstream/src/scanner.c`
against the runtime headers.
