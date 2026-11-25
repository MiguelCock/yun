# tree_sitter_sql (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/DerekStride/tree-sitter-sql`, pinned to `2d08852`
- **Language ABI:** 15
- **Module:** `tree_sitter_sql`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-sql.c3i` — declares `tree_sitter_sql()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `queries/injections.scm` — optional embedded-language query (when upstream ships one).
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> sql
```
