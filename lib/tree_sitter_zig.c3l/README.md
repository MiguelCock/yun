# tree_sitter_zig (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter-grammars/tree-sitter-zig`, pinned to `v1.1.2`
- **Language ABI:** 14
- **Module:** `tree_sitter_zig`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-zig.c3i` — declares `tree_sitter_zig()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/libtree-sitter-zig.a` — prebuilt grammar static library.
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> zig
```
