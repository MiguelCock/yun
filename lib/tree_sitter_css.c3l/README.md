# tree_sitter_css (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter/tree-sitter-css`, pinned to `v0.25.0`
- **Language ABI:** 15
- **Module:** `tree_sitter_css`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-css.c3i` — declares `tree_sitter_css()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> css
```
