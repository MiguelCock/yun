# tree_sitter_r (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/r-lib/tree-sitter-r`, pinned to `v1.3.0`
- **Language ABI:** 14
- **Module:** `tree_sitter_r`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-r.c3i` — declares `tree_sitter_r()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> r
```
