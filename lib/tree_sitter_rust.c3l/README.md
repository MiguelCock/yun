# tree_sitter_rust (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter/tree-sitter-rust`, pinned to `v0.24.2`
- **Language ABI:** 15
- **Module:** `tree_sitter_rust`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-rust.c3i` — declares `tree_sitter_rust()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/libtree-sitter-rust.a` — prebuilt grammar static library.
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> rust
```
