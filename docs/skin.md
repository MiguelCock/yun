# Skins and surfaces

Yun reads an optional `skin` section from `config.json`. The global file lives at
`~/.config/yun/config.json`; a project can override it with `.yun/config.json`.

Use the **Skin** page in Settings (`Ctrl+,`, then `Ctrl+9`) to edit presets,
card/folder styles, title sizes, and each surface without editing JSON. Image
paths support typing and drag-and-drop; relative paths resolve from the global
config folder or `<project>/.yun`.

Saving settings now writes the explicit skin overrides for the selected scope.
Unknown skin keys and comments are normalized away; keep a separate copy if you
need them preserved verbatim.

## Example

```json
{
  "skin": {
    "preset": "paper",
    "surfaces": {
      "app": {
        "image": "wallpapers/space.gif",
        "fit": "cover",
        "opacity": 0.9,
        "speed": 1.0
      },
      "card": {
        "image": "paper/plain.png",
        "fit": "tile",
        "opacity": 0.35,
        "scrim": "#00000055"
      },
      "card_title": { "image": "paper/leather.png", "tint": "#c9a77a" },
      "card_editor": { "image": "paper/ruled.png", "opacity": 0.2 },
      "closed_card": { "image": "paper/ruled.png" },
      "folder": { "image": "paper/manila.png", "fit": "cover" },
      "folder_title": { "image": "paper/tab.png", "tint": "#d8b27a" },
      "topbar": { "image": "glass/noise.png", "opacity": 0.25 },
      "panel": { "image": "glass/noise.png", "opacity": 0.18 },
      "minimap": { "image": "glass/noise.png", "opacity": 0.2 },
      "focus_backdrop": { "image": "wallpapers/space.gif", "fit": "cover" }
    },
    "cards": {
      "style": "paper",
      "closed_height": 112,
      "language_colors": true
    },
    "folders": { "style": "explorer" }
  },
  "canvas": { "card_layout": "deck" }
}
```

Relative image paths are resolved from the directory containing the config file.
Absolute paths are also accepted. PNG, JPG, GIF, and BMP files are supported.
On the Skin page, type or paste a path (`Ctrl+V` or `Shift+Insert`), drag a file
onto the field, or use **Browse for image…** to pick one. The browser starts at the
current image's folder (or the config folder), lists folders first, and filters
to supported extensions; `Up`/`Down` move, `Enter` or a click opens or selects,
`Backspace` goes up, and `Esc` cancels. GIFs are decoded into individual frames,
so each frame fills the surface at its full size and animates using `speed` and
`fps`.

## Surface fields

| Field | Values | Meaning |
| --- | --- | --- |
| `image` | path | Image or GIF to draw |
| `fit` | `cover`, `contain`, `stretch`, `tile` | How the image fills the surface |
| `opacity` | `0.0`–`1.0` | Overall image opacity |
| `tint` | `#rrggbb` / `#rrggbbaa` | Multiplies the image colour |
| `scrim` | `#rrggbbaa` | Readability overlay drawn over the image |
| `speed` | number | GIF playback speed multiplier |
| `fps` | number | GIF playback frame rate |

## Surfaces

`app`, `card`, `card_title`, `card_editor`, `closed_card`, `folder`,
`folder_title`, `topbar`, `panel`, `panel_header`, `minimap`,
`focus_backdrop`, `menu`, `console`.

Panels and menus share the `panel` surface. The minimap also has its own
surface. `card_editor` is drawn inside an open card, under the text.

## Presets

Built-in presets set card/folder styles before per-key overrides:

- `classic` — flat cards and folders.
- `paper` — paper card style and explorer folders.
- `glass` — translucent card style and explorer folders.

Images are not bundled; choose your own files.

## Card and folder styles

`cards.style` accepts `flat`, `paper`, or `glass`. `folders.style` accepts
`classic`, `explorer`, or `tray`. Explorer folders draw a folder tab and a
body; closed folders keep a compact body with a file count and preview lines.
Closed cards draw a taller ruled page (`cards.closed_height`).

`cards.language_colors` controls the language accent on title bars, file icons,
and closed-page spines.

## Card layouts

`canvas.card_layout` is global:

- `grid` — the original three-column grid.
- `deck` — diagonal stacks of up to 10 cards, with every title exposed.
- `fan` — like `deck`, with a wider sideways fan.

Selected cards keep their stable slot; the focused/editing, dragged, and grabbed
card is raised so it stays visible without reshuffling the stack. Use
**Relayout Canvas** (`Ctrl+Alt+L`) after changing the setting in a running
session. Old workspace versions are relaid out once when upgraded.
