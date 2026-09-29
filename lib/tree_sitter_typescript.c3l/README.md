# tree_sitter_typescript (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter/tree-sitter-typescript`, pinned to `v0.23.2`
- **Language ABI:** unknown
- **Module:** `tree_sitter_typescript`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-typescript.c3i` — declares `tree_sitter_typescript()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> typescript
```
