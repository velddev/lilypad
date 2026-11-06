<img src="assets/logo-light.svg#gh-light-mode-only" width="240" alt="Lilypad">
<img src="assets/logo-dark.svg#gh-dark-mode-only" width="240" alt="Lilypad">

Screenshots and screen recordings for niri on Wayland. Pick a region on a frozen screen by clicking a
detected UI element or dragging your own.

    lilypad screen            whole focused monitor
    lilypad region            pick a region on a frozen screen
    lilypad window            click a window
    lilypad record            start a region recording, or stop the running one

The top of `bin/lilypad` lists every command.

## Install

    curl -fsSL https://lilypad.to | sh

## Configure

Create `~/.config/lilypad/config.json`. Every key is optional.

| Key | Type | Default | What it does |
|---|---|---|---|
| `accent` | hex colour | `#B0FF4F` | The default drawing colour, and the first swatch in the toolbar. Applies right away |
| `screenshots` | path | `~/Pictures/Screenshots` | Where screenshots are saved |
| `recordings` | path | `~/Videos/Screen Recordings` | Where recordings are saved |
| `fps` | number | `60` | The frame rate of recordings |

    {
      "accent": "#89B4FA",
      "screenshots": "~/Screenshots",
      "recordings": "~/Recordings",
      "fps": 30
    }
