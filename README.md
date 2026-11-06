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

It clones to `~/.local/share/lilypad`, builds the region detector, links `lilypad` into `~/.local/bin`
and prints the niri binds to add. Running it again updates Lilypad. If packages are missing it asks
before installing them with pacman; on other distros it lists them for you to install.

Needs niri, quickshell, python, grim, imagemagick, wl-clipboard, ffmpeg, gpu-screen-recorder, git and a
C compiler. slurp is the fallback picker, satty the editor.

The first capture starts the UI (`qs -p shell`) and it stays running. To change the accent colour, put
`{"accent": "#89B4FA"}` in `~/.config/lilypad/accent.json`.

## Layout

- `bin/lilypad`: the command, in Python
- `shell/`: the Quickshell UI, with the selector, editor, toolbar, overlay and toast in `capture/`
- `src/lilypad-regions.c`: finds rectangular UI elements in a screenshot. `./build.sh` builds it into `bin/`
