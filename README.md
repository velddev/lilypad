<img src="assets/logo-light.svg#gh-light-mode-only" width="240" alt="Lilypad">
<img src="assets/logo-dark.svg#gh-dark-mode-only" width="240" alt="Lilypad">

Screenshots and screen recordings for niri on Wayland. Pick a region on a frozen screen by clicking a
detected UI element or dragging your own.

    lilypad screen            whole focused monitor
    lilypad region            pick a region on a frozen screen
    lilypad window            click a window
    lilypad record            start a region recording, or stop the running one

The top of `bin/lilypad` lists every command. Screenshots go to `~/Pictures/Screenshots` and
recordings to `~/Videos/Screen Recordings`.

## Install

    curl -fsSL https://lilypad.to | sh

## Configure

Create `~/.config/lilypad/accent.json`. Changes apply right away.

| Key | Type | Default | What it does |
|---|---|---|---|
| `accent` | hex colour | `#B0FF4F` | The default drawing colour, and the first swatch in the toolbar |

    {"accent": "#89B4FA"}
