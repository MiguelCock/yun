# tree_sitter_java (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/tree-sitter/tree-sitter-java`, pinned to `v0.23.5`
- **Language ABI:** 14
- **Module:** `tree_sitter_java`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-java.c3i` — declares `tree_sitter_java()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> java
```
