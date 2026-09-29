# tree_sitter_cpp (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter/tree-sitter-cpp`, pinned to `v0.23.4`
- **Language ABI:** 14
- **Module:** `tree_sitter_cpp`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-cpp.c3i` — declares `tree_sitter_cpp()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/libtree-sitter-cpp.a` — prebuilt grammar static library.
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> cpp
```
