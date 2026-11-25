# Mods and the Lua runtime

Yun links a vendored Lua 5.4 runtime from `lib/lua54.c3l`; users do not need
to install Lua. The runtime is built from the pinned `lib/lua54.c3l/upstream`
submodule with `scripts/build-lua.sh`.

## Building the runtime

```sh
scripts/build-lua.sh linux-x64
scripts/build-lua.sh macos-aarch64
```

The Linux build output (`liblua54.a`) is committed so a plain `c3c build`
works on the development machine. CI and release builds run the script before
compiling Yun for each target. Windows uses the prebuilt import library and DLL
already shipped in the submodule.

The Lua core is compiled as C with `LUA_USE_POSIX` on Linux/macOS and
`LUA_USE_WINDOWS` on Windows. Linux additionally links `-lm` and `-ldl`; macOS
links `-lm`.
