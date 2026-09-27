# Language servers (LSP)

Yun drives hover, go-to-definition, completion, and diagnostics through language
servers. Servers are optional: if the binary is not installed, the language just
has no LSP features (no error, no crash).

## How it works

1. Yun detects a document's **language id** from its file extension.
2. It looks up a **default server command** for that id.
3. It starts the server once per language, rooted at the project folder, and
   sends `textDocument/didOpen` with the language id.

The id is also the key used to override the command in config.

## Supported languages

| id | extensions | default command |
| --- | --- | --- |
| `c3` | `.c3` `.c3i` | `c3lsp` |
| `c` | `.c` `.h` | `clangd` |
| `cpp` | `.cpp` `.cc` `.cxx` `.hpp` `.hh` `.hxx` | `clangd` |
| `python` | `.py` | `pyright-langserver --stdio` |
| `javascript` | `.js` `.mjs` `.cjs` `.jsx` | `typescript-language-server --stdio` |
| `typescript` | `.ts` `.tsx` | `typescript-language-server --stdio` |
| `go` | `.go` | `gopls` |
| `rust` | `.rs` | `rust-analyzer` |
| `zig` | `.zig` `.zon` | `zls` |
| `odin` | `.odin` | `ols` |
| `v` | `.v` | `v-analyzer` |
| `nim` | `.nim` `.nims` | `nimlangserver` |

The defaults are best-effort. A language with no entry (and no override) is
ignored by the LSP.

## Configuration

Override the command for a language id under the `lsp` section of the config
(global or project scope; project wins):

```json
{
  "lsp": {
    "c3": "c3lsp",
    "python": "pylsp",
    "cpp": "clangd --background-index"
  }
}
```

- Keys are language ids (from the table above).
- Values are the full command; arguments are split on whitespace (there is no
  shell quoting, so avoid paths with spaces).
- An override takes precedence over the default command.
- A key that is not a detected language id is accepted but unused (unless a
  future language uses that id).

## Notes

- The server is spawned with the project root as its workspace; without an open
  project, no server is started.
- Diagnostics arrive via `textDocument/publishDiagnostics` and show in the
  problems panel and as squiggles in the editor.
- The language id sent in `didOpen` matches the table id, so servers that key
  behavior on `languageId` (e.g. `clangd` for `c` vs `cpp`) work as expected.
