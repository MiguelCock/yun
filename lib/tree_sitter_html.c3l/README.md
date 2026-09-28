# tree_sitter_html (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter/tree-sitter-html`, pinned to `v0.23.2`
- **Language ABI:** 14
- **Module:** `tree_sitter_html`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-html.c3i` — declares `tree_sitter_html()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> html
```
