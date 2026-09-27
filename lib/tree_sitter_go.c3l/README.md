# tree_sitter_go (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter/tree-sitter-go`, pinned to `v0.25.0`
- **Language ABI:** 15
- **Module:** `tree_sitter_go`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-go.c3i` — declares `tree_sitter_go()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/libtree-sitter-go.a` — prebuilt grammar static library.
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> go
```
