# tree_sitter_v (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/undivisible/tree-sitter-v`, pinned to `v0.0.1-9-ged235d6`
- **Language ABI:** 13
- **Module:** `tree_sitter_v`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-v.c3i` — declares `tree_sitter_v()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/libtree-sitter-v.a` — prebuilt grammar static library.
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> v
```
