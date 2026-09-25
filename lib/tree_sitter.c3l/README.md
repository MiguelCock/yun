# tree-sitter (C3L)

C3 bindings for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `tree-sitter/tree-sitter`, pinned to `v0.26.13`
- **Language ABI:** 15 (min compatible 13)
- **Module:** `tree_sitter`
- **License:** MIT (`LICENSE`)

## Layout

- `tree-sitter.c3i` — opaque types (`TSParser`, `TSTree`, `TSLanguage`, `TSQuery`, `TSQueryCursor`),
  value structs (`TSNode`, `TSPoint`, `TSInputEdit`, `TSRange`, ...), and the `ts_*` C API.
- `linked-libs/<target>/libtree-sitter.a` — prebuilt runtime static library.
- `upstream/` — the pinned runtime source (git submodule), used to build the static library.

## Building the static libraries

The prebuilt `linux-x64` library is committed so `c3c build` works out of the box. To
regenerate it (or produce another target with a matching toolchain):

```sh
scripts/build-tree-sitter.sh linux-x64
```

The script compiles `upstream/lib/src/lib.c` into `linked-libs/<target>/libtree-sitter.a`.
For `macos-aarch64` / `windows-x64`, run the same script with `CC`/`AR` pointing at a
cross toolchain that targets that platform; there is no silent fallback.

## Grammars

Language grammars live in their own libraries (`tree_sitter_c`, `tree_sitter_python`,
`tree_sitter_javascript`, `tree_sitter_c3`), each depending on this runtime.
