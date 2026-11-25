# tree_sitter_graphql (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/bkegley/tree-sitter-graphql`, pinned to `5e66e96`
- **Language ABI:** 13
- **Module:** `tree_sitter_graphql`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-graphql.c3i` — declares `tree_sitter_graphql()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `queries/injections.scm` — optional embedded-language query (when upstream ships one).
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> graphql
```
