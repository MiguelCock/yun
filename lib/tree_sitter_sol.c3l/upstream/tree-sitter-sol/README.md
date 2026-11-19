# tree-sitter-sol

Tree-sitter grammar for SOL.

The grammar is intentionally editor-focused. The SOL compiler's parser remains
the semantic authority; this grammar provides tolerant syntax trees for
highlighting, folds, indentation, text objects, and tags.

The checked-in parser targets tree-sitter ABI 14 so it loads in Neovim 0.11+.
Regenerate with `--abi 14` when changing the grammar.

Canonical queries live at the repository root in
[`queries/sol/`](../queries/sol/). Neovim and Yun consume those files directly;
the grammar package does not duplicate them.

## Build

```sh
cd tree-sitter-sol
tree-sitter generate --abi 14
tree-sitter test
tree-sitter build
```

Install the parser for Neovim with
[`editors/nvim/scripts/install-parser.sh`](../editors/nvim/scripts/install-parser.sh).
