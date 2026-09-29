# tree_sitter_kotlin (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/fwcd/tree-sitter-kotlin`, pinned to `0.3.8`
- **Language ABI:** 14
- **Module:** `tree_sitter_kotlin`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-kotlin.c3i` — declares `tree_sitter_kotlin()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> kotlin
```
