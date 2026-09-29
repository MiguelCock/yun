# tree_sitter_odin (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter-grammars/tree-sitter-odin`, pinned to `v1.3.0`
- **Language ABI:** 14
- **Module:** `tree_sitter_odin`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-odin.c3i` — declares `tree_sitter_odin()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/libtree-sitter-odin.a` — prebuilt grammar static library.
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> odin
```
