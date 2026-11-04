# diffary

A Ghostty terminal with a live sidebar of what your branch changed vs its base.

![unified diff](docs/screenshots/diff-unified.png)

| side-by-side | dark theme | sidebar at bottom |
|---|---|---|
| ![](docs/screenshots/diff-side-by-side.png) | ![](docs/screenshots/diff-dark.png) | ![](docs/screenshots/sidebar-bottom.png) |

Regenerate: `scripts/screenshot.sh docs/screenshots/<name>.png [diffary flags]`

## Install

```sh
scripts/bundle.sh --install                       # → ~/Applications/Diffary.app
ln -sf "$PWD/scripts/diffary" ~/.local/bin/diffary
```

Needs the Command Line Tools (no Xcode) and `gh` access to this repo's releases (GhosttyKit is built in CI, on the `macos-15` GitHub Actions runner).

On a Command Line Tools-only machine plain `swift test` fails; run `scripts/test.sh` instead.

## Use

```sh
diffary [repo] [--config FILE] [--base BRANCH] [--set key=value]...
```

## Config

`$XDG_CONFIG_HOME/diffary/config.toml` (default `~/.config/diffary/config.toml`). Reloaded on save.

```toml
base_branch = "master"        # falls back to "main"

[layout]
sidebar = "right"             # right | left | bottom
sidebar_size = 0.35           # 0.1–0.9, fraction of window
diff_position = "below_list"  # below_list | beside_list | replace_terminal

[diff]
view = "unified"              # unified | side_by_side
context_lines = 3             # lines before/after each change, 0–1000
ignore_whitespace = false
syntax_highlight = true

[appearance]
font = "JetBrains Mono"       # falls back to system monospace if missing
font_size = 13
theme = "auto"                # auto | light | dark | <user theme name>
```

See `docs/superpowers/specs/2026-11-04-diffary-design.md` for every key and the theme format.
Themes: `~/.config/diffary/themes/<name>.toml`, selected with `[appearance] theme = "<name>"`.
Terminal settings come from Ghostty's own config.

## Bumping Ghostty

Put a new sha in `GHOSTTY_COMMIT` and push. CI publishes a new GhosttyKit; `scripts/fetch-ghosttykit.sh` picks it up.
The embedding API isn't stable, so expect to fix `TerminalView`/`GhosttyRuntime` after a bump.
