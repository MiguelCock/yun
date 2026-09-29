# tree_sitter_lua (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter-grammars/tree-sitter-lua`, pinned to `v0.5.0`
- **Language ABI:** 15
- **Module:** `tree_sitter_lua`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-lua.c3i` — declares `tree_sitter_lua()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> lua
```
