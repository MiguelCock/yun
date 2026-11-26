# Language servers

Language servers are optional. If a server binary is not installed, the language
simply keeps tree-sitter highlighting and reports no LSP features.

## Setup

Configure servers under the `lsp` section:

```json
{
  "lsp": {
    "c3": "c3lsp",
    "python": "pylsp",
    "typescript": "typescript-language-server --stdio"
  }
}
```

Yun detects the language id from the file extension and starts one server per
language, rooted at the project. An explicit mapping overrides the built-in
default. Server capabilities decide which features are enabled.

## Features

- hover
- go to definition (`F12`)
- completion (`Ctrl+Space`)
- diagnostics and the Problems panel (`Ctrl+Shift+M`)
- document and workspace symbols (`Ctrl+Shift+O`)
- references and rename
- code actions
- signature help
- semantic tokens
- inlay hints where supported

Diagnostics appear on cards and in the Problems panel.

## Troubleshooting

- Check the LSP status in the top bar.
- Run the server command manually in the project root.
- Make sure the server matches your toolchain version (especially `zls`).
- Some servers need a project manifest or build file in the root.
- Language server stdout/stderr is captured in the LSP log/console.

See the [technical LSP reference](../lsp.md) for supported ids, defaults, and
protocol details.
