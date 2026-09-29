# tree_sitter_erlang (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/WhatsApp/tree-sitter-erlang`, pinned to `0.20`
- **Language ABI:** 14
- **Module:** `tree_sitter_erlang`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-erlang.c3i` — declares `tree_sitter_erlang()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `queries/injections.scm` — optional embedded-language query (when upstream ships one).
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> erlang
```
