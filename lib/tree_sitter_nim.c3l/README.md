# tree_sitter_nim (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/alaviss/tree-sitter-nim`, pinned to `0.6.2`
- **Language ABI:** 14
- **Module:** `tree_sitter_nim`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-nim.c3i` — declares `tree_sitter_nim()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/libtree-sitter-nim.a` — prebuilt grammar static library.
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> nim
```
