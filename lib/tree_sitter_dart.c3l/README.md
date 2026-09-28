# tree_sitter_dart (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/UserNobody14/tree-sitter-dart`, pinned to `be07cf7`
- **Language ABI:** 15
- **Module:** `tree_sitter_dart`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-dart.c3i` — declares `tree_sitter_dart()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `queries/injections.scm` — optional embedded-language query (when upstream ships one).
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> dart
```
