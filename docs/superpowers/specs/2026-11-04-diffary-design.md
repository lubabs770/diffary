# diffary — design

A native macOS app: a Ghostty terminal plus a live sidebar listing files the
current branch changed against its base branch, with a per-file diff view.
The AI agent, herdr, tmux, and shell all run inside the terminal; diffary owns
none of that, it only watches the repo.

## Goals

- Embed a real Ghostty terminal (libghostty, as Ghostty.app does).
- Show added / modified / deleted / untracked files vs the base branch, live.
- Click a file → its diff, rendered per config.
- Everything configurable through XDG config files; no settings UI.
- Launchable from the terminal with flags.

## Non-goals

- Staging, committing, editing, or any git write.
- Configuring the AI or terminal (Ghostty's own config covers the terminal).
- Multiple repos per window, following the terminal's cwd.
- Windows/Linux.

## What "changed" means

Base = `git merge-base <base_branch> HEAD`. The list is the working tree vs
that base, so it includes committed branch work, uncommitted edits, and
untracked files:

- `git diff --name-status -M <base>` and `git diff --numstat -M <base>` (tracked)
- `git ls-files --others --exclude-standard` (untracked, shown as added)

`base_branch` defaults to `master`, falling back to `main` if `master` does not
exist. If neither exists, or the folder is not a git repo, the sidebar shows
that message and the terminal still works.

## Units

Each unit has one job and is testable alone.

| Unit | Does | Depends on |
|------|------|------------|
| `TerminalView` | NSView hosting a `ghostty_surface`; owns the `ghostty_app` lifecycle, input, resize. Knows nothing about git. | GhosttyKit |
| `GitChanges` | Runs the `git` CLI, returns `[FileChange]` (path, old path, status, +/-). Only place that lists changes. | `git` on PATH |
| `DiffLoader` | Runs `git diff -U<n> [-w] <base> -- <path>` (or `--no-index /dev/null <path>` for untracked), parses into hunks/lines. | `git` |
| `RepoWatcher` | FSEvents on the repo root, debounced 300 ms, ignores `.git/objects`, `.git/logs`; fires a refresh. | FSEvents |
| `FileListView` | SwiftUI list: status letter, path, +/- counts. | `[FileChange]` |
| `DiffView` | Renders hunks unified or side-by-side, optional syntax highlight. | hunks, `Theme`, `Settings` |
| `LayoutView` | Places terminal, list, diff according to `[layout]`. Views don't know their position. | `Settings` |
| `Settings` | Loads + validates TOML, watches the file, publishes changes. | TOML parser |
| `Theme` | Loads built-in or user theme files into colors. | `Settings` |
| `CLI` | Parses launch flags into a launch config. | swift-argument-parser |

## Config

Location (XDG): `$XDG_CONFIG_HOME/diffary/config.toml`, default
`~/.config/diffary/config.toml`. Overridable with `--config`. Missing file =
all defaults. Reloaded live on save.

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
theme = "ghostty"             # ghostty (match the terminal) | auto | light | dark | <user theme name>
titlebar = false              # true shows the window title bar
```

Invalid values fall back to the default for that key and show one warning line
at the top of the sidebar naming the key. The app never refuses to start over
config.

Terminal font/colors/keys stay in Ghostty's own config, which libghostty loads
as usual.

## Themes

Built-in: `light`, `dark`. `auto` follows macOS appearance. `ghostty` (default)
uses the terminal's background, foreground and selection colors from Ghostty's
config, with diff and syntax colors from `dark` or `light` by background brightness.

User themes: `$XDG_CONFIG_HOME/diffary/themes/<name>.toml`, selected with
`theme = "<name>"`. Any key missing falls back to the built-in `dark` (or
`light` if the theme sets `base = "light"`).

```toml
base = "dark"
background = "#1e1e2e"
foreground = "#cdd6f4"
sidebar_background = "#181825"
selection = "#313244"
added_bg = "#a6e3a120"
added_fg = "#a6e3a1"
removed_bg = "#f38ba820"
removed_fg = "#f38ba8"
hunk_header = "#89b4fa"
line_number = "#6c7086"
status_added = "#a6e3a1"
status_modified = "#f9e2af"
status_deleted = "#f38ba8"
status_renamed = "#89b4fa"

[syntax]                      # optional; highlighter defaults otherwise
keyword = "#cba6f7"
string = "#a6e3a1"
comment = "#6c7086"
number = "#fab387"
type = "#f9e2af"
```

Theme files reload live too.

## CLI

A `diffary` launcher script on PATH runs `open -n -a Diffary --args …` with
paths made absolute, so the terminal you launch from stays free.

```
diffary [<repo>] [--config <file>] [--base <branch>] [--set <key>=<value>]...
```

- `<repo>`: folder to watch; default the current directory.
- `--config <file>`: use this config file instead of the XDG path.
- `--base <branch>`: override `base_branch` for this window.
- `--set key=value`: override any config key for this window, dotted
  (`--set diff.view=side_by_side`). Repeatable. Applied after the file.
- `--help`, `--version`.

Each launch opens a new window on that repo; the terminal starts in `<repo>`.

## Data flow

1. Launch → CLI → `Settings` (file + overrides) → window on `<repo>`.
2. `TerminalView` starts a shell in `<repo>`.
3. `RepoWatcher` event → `GitChanges` (off main thread) → `FileListView`.
4. Click a file → `DiffLoader` (off main thread) → `DiffView`.
   If the open file changes, its diff reloads too.
5. Config/theme save → `Settings` publishes → views re-render.

## Errors

- `git` failure: sidebar shows the stderr line; terminal unaffected.
- Huge diff (> 20k lines) or binary: show "binary file" / "diff too large —
  open in terminal" instead of rendering.
- Ghostty surface fails to init: window shows the error text; sidebar still works.

## Build & CI

- No Xcode locally. Command Line Tools + Swift 6.4, SwiftPM project.
- GitHub Actions (macOS runner, has Xcode + Zig) builds
  `GhosttyKit.xcframework` from a pinned Ghostty commit, publishes it as a
  release asset. Rebuilt only when the pin changes.
- `Package.swift` consumes it as a `binaryTarget` (URL + checksum).
- Local: `swift build` + `scripts/bundle.sh` wraps the binary into
  `Diffary.app` with an `Info.plist`. Seconds, no signing.
- CI also runs `swift build` + `swift test` on each push.
- Dependencies: GhosttyKit, swift-argument-parser, a TOML parser
  (TOMLKit), a syntax highlighter (chosen in the plan; must work without
  Xcode).

## Testing

- `GitChanges` / `DiffLoader`: tests against temp git repos built in the test
  (add, modify, delete, rename, untracked, no base branch).
- `Settings` / `Theme`: parse, defaults, invalid-value fallback, `--set` merge.
- `CLI`: flag parsing.
- `TerminalView` / views: manual check by running the app.

## Risks

- libghostty's embedding API is unstable: pinned commit, bumped deliberately.
- Building GhosttyKit in CI may need Ghostty-version-specific steps; first CI
  run is the spike that proves it.
