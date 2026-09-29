# tree_sitter_v (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `nedpals/tree-sitter-v`, pinned to `fee18d64a5`
- **Language ABI:** 13
- **Module:** `tree_sitter_v`
- **License:** MIT (`LICENSE`)

## Layout

- `tree-sitter-v.c3i` — declares `tree_sitter_v()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Notes

`nedpals/tree-sitter-v` is the original grammar (unmaintained since 2022) but its
generated `parser.c`/`node-types.json` are consistent with `queries/highlights.scm`.
The maintained `undivisible` fork was not usable here: its committed parser was
out of sync with its query (`builtin_type` missing), so the query failed to compile.

## Building

```sh
scripts/build-tree-sitter.sh <target> v
```
