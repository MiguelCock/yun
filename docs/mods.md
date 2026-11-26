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

## Installing mods

Yun scans two folders at startup:

- **Global:** `<platform config dir>/yun/mods` (for example
  `~/.config/yun/mods` on Linux).
- **Project:** `<project root>/.yun/mods`.

Only `.lua` files are loaded. The project folder is scanned after a project
opens. Within each folder, files are loaded in alphabetical order by file name;
the global folder is loaded before the project folder. If a global and a project
mod have the same base name, the global mod wins and the project copy is
skipped; rename one of them to load both. Mods are sandboxed individually and a
mod that fails to load is reported and skipped; the rest keep working.

A mod may declare a name and version by returning a table from its top-level
chunk, or by setting globals:

```lua
MOD_NAME = "hello"
MOD_VERSION = "1.0.0"

return { name = "hello", version = "1.0.0" }
```

The loader logs the name, version, and path of every loaded mod. Syntax and
startup failures are logged; load failures and mods disabled after repeated
errors are also reported through the notification API.

## Configuration

| Key | Default | Meaning |
| --- | --- | --- |
| `mods.enabled` | `true` | Load mods at all. |
| `mods.allow_render` | `false` | Allow `on_draw` and the `yun.draw` API. |
| `mods.allow_input` | `false` | Allow `on_input`, `on_update`, and the input helpers. |

Settings can be global (`<config dir>/yun/config.json`) or project-local
(`<project>/.yun/config.json`). Rendering and input are **off by default** for
community mods; enable them only for mods you trust.

## API surface

Every mod gets its own `yun` table. The API is versioned and read-only.

```lua
yun.api_version        -- integer, currently 1
yun.host_version       -- Yun version string
yun.mod_name           -- name of the running mod
```

### Reading the project

All returned strings and tables are copies owned by Lua. Card ids are stable
for the lifetime of the current project.

```lua
local project = yun.project()
-- { root, name, card_count, focused, selected } or nil

local card = yun.card(0)
-- { valid, id, path, name, language, open, dirty, missing, focused,
--   cursor, selection_anchor, line_count, text_length } or nil

local focused = yun.focused()       -- card table or nil
local cards = yun.cards()           -- array of card tables (max 512)
local selection = yun.selection()
-- { valid, card, path, start, end, anchor, cursor, text }
-- Use selection['end'] in Lua: `end` is a reserved word.

local text, truncated = yun.buffer(card_id, start_byte, length)
local total = yun.buffer_length(card_id)
```

`yun.buffer` copies at most 1 MiB per call. `truncated` is true when fewer
bytes than requested were returned (larger request, cap, or end of file).

### Notifications, logs, menus, and commands

```lua
yun.notify("Saved!")
yun.log("info", "hello from a mod")       -- level: debug/info/warn/error
yun.add_menu_item("My action", function() ... end)
yun.register_command("my.action", "My action", function() ... end)
```

Registered commands appear in the command palette and registered menu items in
the canvas context menu. Command ids are global; registering an id twice raises
a Lua error. Commands and menu items are removed when the mod is unloaded or
disabled.

### Events

Handlers are plain Lua functions. Every call is isolated with `pcall` and a
traceback; an error is logged and does not stop other mods.

```lua
yun.on_startup(function(info) ... end)
yun.on_file_open(function(card) ... end)
yun.on_file_save(function(card) ... end)
yun.on_file_close(function(card) ... end)
yun.on_command(function(command) ... end)
yun.on_selection(function(selection) ... end)
yun.on_update(function(dt) ... end)
yun.on_draw(function() ... end)
yun.on_input(function(input) ... end)
```

- `on_startup` receives `{ api_version, host_version, mod_name }`.
- File events receive the same table shape as `yun.card(id)`.
- `on_command` receives `{ id, name, label, card }`. Built-in commands use
  their numeric id; mod commands report `id = -1` and their string name.
- `on_selection` receives `{ card, path, start, end, anchor, cursor, text }`.
- `on_update` receives the frame delta in seconds. It runs when at least one of
  render/input is enabled.
- `on_draw` runs once per frame when `mods.allow_render` is on.
- `on_input` runs once per frame when `mods.allow_input` is on and receives
  `{ mouse = {x, y}, wheel, left_down, right_down, left_pressed, right_pressed }`.

Handlers are called in registration order. Registering a second handler for the
same event adds it to the list. A reentrancy guard prevents a handler from
recursively triggering the same dispatch path.

### Drawing

Drawing is available only inside `on_draw` and when `mods.allow_render` is
enabled. Coordinates are screen pixels. Colors are either packed `0xRRGGBBAA` / `0xRRGGBB` integers or
tables `{r, g, b, a}` with 0-255 components.

```lua
yun.draw.clear(color)
yun.draw.rect(x, y, w, h, color, filled)          -- filled defaults to true
yun.draw.rect_lines(x, y, w, h, color, thickness)
yun.draw.line(x1, y1, x2, y2, color, thickness)
yun.draw.circle(x, y, radius, color, filled)
yun.draw.text(text, x, y, size, color)
yun.draw.image(path, x, y, w, h, tint)            -- alias: yun.draw.texture
```

Image paths are relative to the mod folder. Absolute paths, drive letters, and
`..` segments are rejected. Missing or invalid assets raise a Lua error instead
of crashing the host. Textures are cached per mod and released when the mod is
unloaded.

Use `yun.set_overlay("below")` or `yun.set_overlay("above")` (the default) to
choose whether the mod draws before or after the app UI. `yun.overlay()` returns
the current layer.

### Input

When `mods.allow_input` is enabled:

```lua
yun.is_key_down("a")       -- also "space", "escape", "left", "f1", numbers
yun.is_key_pressed("space")
yun.mouse()                -- { x, y, wheel, left, right, middle, left_pressed, right_pressed }
yun.screen_size()          -- { width, height }
```

When input is disabled, `is_key_down`/`is_key_pressed` return `false` and
`yun.mouse()` returns `nil`; the editor keeps keyboard focus. Input is read-only
and never captured by mods.

### Capabilities

```lua
yun.has_capability("read")     -- always true
yun.has_capability("notify")   -- always true
yun.has_capability("render")   -- mods.allow_render
yun.has_capability("input")    -- mods.allow_input
local caps = yun.capabilities()
```

The API has no raw pointers, file writes, process spawning, network access, or
OS handles. `io`, `os`, `package`, `debug`, `require`, `dofile`, `loadfile`,
`load`, `print`, and `warn` are removed from the mod state. Available libraries
are `base`, `string`, `table`, `math`, and `utf8`.

## Limits and failure policy

Each mod has a separate Lua state:

- Memory: 8 MiB cap enforced by a custom allocator. Exceeding it fails the call
  with "not enough memory" and disables the mod.
- Instructions: 2,000,000 per event/command call and 200,000 per frame hook.
  An instruction-count hook interrupts infinite loops with "instruction budget
  exceeded" and disables the mod.
- Frame time: 8 ms per mod per frame. Over-budget hooks are warned, skipped for
  two frames, and disabled after five overruns.
- Drawing: at most 4096 primitives per `on_draw` call and 16 textures per mod.
- Text: at most 4096 bytes per `draw.text` call.
- Registration: at most 256 event handlers per mod, 256 commands in total, and
  32 context-menu items in total.

Repeated ordinary errors disable a mod after three failures. A failure caused by
a memory or instruction limit disables it immediately. Disabled mods stay
unloaded for the session and are reported in a notification; the IDE and the
other mods keep running.

## Security notes

Mods run in-process with a restricted Lua state. This is a guardrail, not an
OS sandbox:

- A bug in a host binding or in the Lua runtime can still crash Yun.
- Asset paths reject traversal and absolute paths, but symlinks placed inside a
  mod folder are not resolved; do not install mods you do not trust.
- Mods can consume CPU up to the instruction/frame budgets before they are
  stopped.
- There is no hot reload; edit a mod and restart Yun.

If you need stronger isolation, run Yun inside a container or OS sandbox.

## Example mod

Save as `~/.config/yun/mods/hello.lua`:

```lua
MOD_VERSION = "1.0.0"

local opened = 0

yun.on_startup(function()
	yun.notify("Hello from a Yun mod")
end)

yun.on_file_open(function(card)
	opened = opened + 1
	yun.log("info", "opened " .. card.path .. " (" .. card.language .. ")")
end)

yun.on_command(function(command)
	if command.name == "save" then
		yun.notify("Saved " .. opened .. " files so far")
	end
end)

yun.on_update(function(dt)
	-- Runs when mods.allow_render or mods.allow_input is enabled.
end)

yun.on_draw(function()
	if not yun.has_capability("render") then return end
	local size = yun.screen_size()
	yun.draw.rect(20, size.height - 60, 180, 32, 0x202020CC)
	yun.draw.text("hello", 32, size.height - 52, 18, 0xFFFFFFFF)
end)

yun.register_command("hello.greet", "Hello: greet", function()
	yun.notify("Hello!")
end)
```
