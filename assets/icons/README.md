# Icon themes

Yun vendors generated PNG icons from two VS Code icon projects:

- **Codicons** — `microsoft/vscode-codicons`, CC BY 4.0. UI/action icons,
  rasterized as white silhouettes and tinted by the theme.
- **Material Icon Theme** — `PKief/vscode-material-icon-theme`, MIT.
  File/language icons.
- **vscode-icons** — `vscode-icons/vscode-icons`, MIT. Alternate file/language
  icons.

Pinned revisions are recorded in `scripts/fetch-icon-themes.sh`. Regenerate the
assets with:

```sh
scripts/fetch-icon-themes.sh
```

## User overrides

Put replacement PNGs in the platform config directory:

- Linux: `~/.config/yun/icons/<theme>/<name>.png`
- macOS: `~/Library/Application Support/yun/icons/<theme>/<name>.png`
- Windows: `%APPDATA%/yun/icons/<theme>/<name>.png`

`<theme>` is `codicons`, `material`, or `vscode`. The bundled files are used when
no user override exists. UI icons are white and tinted at draw time; file icons
keep their original colors.

## Licenses

- `LICENSE-codicons` — Codicons, CC BY 4.0.
- `LICENSE-material` — Material Icon Theme, MIT.
- `LICENSE-vscode-icons` — vscode-icons, MIT.

These notices must be kept with the assets and in redistributed builds.
