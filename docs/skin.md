# Skins and surfaces

Yun reads an optional `skin` section from `config.json`. The global file lives at
`~/.config/yun/config.json`; a project can override it with `.yun/config.json`.

Settings changes made in the app preserve the `skin` section.

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
Absolute paths are also accepted. PNG, JPG, and GIF files are supported.

## Surface fields

| Field | Values | Meaning |
| --- | --- | --- |
| `image` | path | Image or GIF to draw |
| `fit` | `cover`, `contain`, `stretch`, `tile` | How the image fills the surface |
| `opacity` | `0.0`–`1.0` | Overall image opacity |
| `tint` | `#rrggbb` / `#rrggbbaa` | Multiplies the image colour |
| `scrim` | `#rrggbbaa` | Readability overlay drawn over the image |
| `speed` | number | GIF playback speed multiplier |
| `fps` | number | GIF frame rate when the file format does not provide one |

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
body; closed cards draw a taller ruled page (`cards.closed_height`).

`cards.language_colors` controls the language accent on title bars, file icons,
and closed-page spines.

## Card layouts

`canvas.card_layout` is global:

- `grid` — the original three-column grid.
- `deck` — overlapping stacks of up to 10 cards, with every title exposed.
- `fan` — like `deck`, with a sideways fan.

The selected card is promoted to the bottom of its stack and expands, so its
body is editable while the titles above stay readable. Use **Relayout Canvas**
(`Ctrl+Alt+L`) after changing the setting in a running session.
