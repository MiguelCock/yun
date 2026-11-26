# Troubleshooting

## Yun opens without syntax highlighting or import arrows

Grammar libraries are built separately from the executable. In a source build:

```sh
scripts/build-tree-sitter.sh linux-x64
```

Release archives include a `grammars/` directory; keep it next to the executable.
`YUN_GRAMMAR_DIR` can point at a custom grammar directory.

## Language features are missing

- Confirm the language server binary is on `PATH`.
- Run the server command manually from the project root.
- Check the top-bar LSP status and the LSP output.
- Make sure the server version matches the compiler/toolchain (`zls` is a common
  source of version mismatches).
- Some servers need a manifest/build file to initialize the project.

## Assets or fonts are missing

Yun resolves bundled assets from the current directory first, then the executable
directory. Run the release binary from its extracted folder, or keep `assets/`
next to it. Set `YUN_DEBUG_UI=1` to see the paths it tries.

## The window feels slow

- Hold `F3` to show frame/update/draw/scan timings and awake/asleep editors.
- Zoom in; at very low zoom Yun deliberately uses simplified card drawing.
- Disable import arrows or use related-only mode for a dense canvas.
- Turn off external reload polling if the project is on a slow filesystem.
- Very large projects remain an active performance area; include the `F3`
  numbers and project size in an issue.

## A file changed on disk

Yun watches open buffers and asks whether to reload or keep your version. This is
controlled by `app.external_reload` and `app.reload_poll`.

## Recover unsaved work

Yun journals dirty buffers under `.yun/recovery/`. If it exits unexpectedly,
reopen the project and choose **Restore unsaved work**. Choosing **Discard**
clears the journal.

## Reset the workspace

Close Yun, then remove or rename:

```
<project>/.yun/workspace.json
```

Yun will lay out the project again. The import/symbol caches are disposable and
can be removed with `.yun/cache/`.

## Windows notes

- Console commands use `cmd /C`; interactive terminals use ConPTY and `cmd.exe`.
- The console code page is switched to UTF-8 (`chcp 65001`).
- DPI scaling follows the monitor; `YUN_DEBUG_UI=1` prints the resolved scale.

Windows runtime validation is tracked in the issue backlog. Please include the
Windows version, GPU/driver, and `YUN_DEBUG_UI=1` output in reports.
