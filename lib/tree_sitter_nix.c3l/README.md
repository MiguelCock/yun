# tree_sitter_nix (C3L)

Grammar for the [tree-sitter](https://github.com/tree-sitter/tree-sitter) runtime.

- **Upstream:** `https://github.com/nix-community/tree-sitter-nix`, pinned to `v0.3.0`
- **Language ABI:** 13
- **Module:** `tree_sitter_nix`
- **License:** see `LICENSE`

## Layout

- `tree-sitter-nix.c3i` — declares `tree_sitter_nix()` returning the `TSLanguage*`.
- `queries/highlights.scm` — bundled highlight query, consumed by the editor.
- `queries/injections.scm` — optional embedded-language query (when upstream ships one).
- `linked-libs/<target>/` — built grammar library (shared by default; `.a` with `--static`).
- `grammar.conf` — build options (src/queries/lib) read by the build scripts.
- `upstream/` — the pinned grammar source (git submodule).

## Building

```sh
scripts/build-tree-sitter.sh <target> nix
```
