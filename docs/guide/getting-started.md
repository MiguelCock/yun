# Getting started

## Download a build

Prebuilt archives are published on the [releases page](https://github.com/MiguelCock/yun/releases/latest):

| Platform | Archive |
| --- | --- |
| Linux x64 | `yun-<version>-linux-x64.tar.gz` |
| macOS arm64 | `yun-<version>-macos-aarch64.tar.gz` |
| Windows x64 | `yun-<version>-windows-x64.zip` |

Extract the archive and run `yun` (`yun.exe` on Windows). The release archive
includes the executable, fonts, icons, grammar libraries, and license files.

There is currently no Linux arm64 or macOS x64 release build. Build from source
for those targets.

## Build from source

Yun needs the external C3 compiler. CI builds with **c3c 0.8.4**.

```sh
git clone --recurse-submodules https://github.com/MiguelCock/yun.git
cd yun
scripts/build-tree-sitter.sh linux-x64
c3c build
c3c run
```

On Linux, install the native dependencies listed in
[`ci.yml`](https://github.com/MiguelCock/yun/blob/main/.github/workflows/ci.yml):
`libx11-dev libxrandr-dev libxinerama-dev libxi-dev libxcursor-dev libgl1-mesa-dev`.

Run a project directly:

```sh
c3c run -- /path/to/project
```

## First project

1. Open a folder from the CLI or with **Open** in the top bar.
2. The project opens as file cards and folder clusters.
3. Select a card and press `Enter` or `i` to edit it.
4. Press `Esc` to return to canvas navigation.
5. Save with `Ctrl+S`.

The canvas layout, camera, open console sessions, and command history are stored
in `.yun/workspace.json` inside the project. Yun also writes disposable import
and symbol caches under `.yun/cache/`, and a recovery journal while dirty
buffers exist.

## Next

- [Canvas and navigation](canvas.md)
- [Editing](editing.md)
- [Settings and keybindings](settings.md)
