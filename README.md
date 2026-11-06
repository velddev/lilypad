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

`~/.config/lilypad/accent.json`:

    {"accent": "#89B4FA"}

## Layout

- `bin/lilypad`: the command, in Python
- `shell/`: the Quickshell UI, with the selector, editor, toolbar, overlay and toast in `capture/`
- `src/lilypad-regions.c`: finds rectangular UI elements in a screenshot. `./build.sh` builds it into `bin/`
