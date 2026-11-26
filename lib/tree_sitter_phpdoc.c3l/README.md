# tree_sitter_phpdoc (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/claytonrcarter/tree-sitter-phpdoc`, pinned to `v0.1.8`
- **Language ABI:** 14
- **Module:** `tree_sitter_phpdoc`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-phpdoc.c3i` — declares `tree_sitter_phpdoc()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `queries/injections.scm` — optional embedded-language query (when upstream ships one).
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> phpdoc
```
