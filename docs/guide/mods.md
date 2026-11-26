# Mods

Yun embeds Lua 5.4 and loads mods from:

- `<config dir>/yun/mods`
- `<project>/.yun/mods`

A mod is a directory with a Lua entry point and a manifest. Mods can add palette
commands, context-menu items, notifications, logs, lifecycle hooks, and optional
rendering/input overlays.

## Safety

Mods run in separate Lua states with memory, instruction, and per-frame budgets.
Repeated errors or budget overruns disable the mod instead of taking down the
editor. Rendering and input capabilities are opt-in:

```json
{
  "mods": {
    "enabled": true,
    "allow_render": false,
    "allow_input": false
  }
}
```

Mods are trusted local code once enabled; the budgets are a stability guard, not
a security boundary against a malicious local mod.

See the [mods reference](../mods.md) for the manifest, event list, API, and
examples.
