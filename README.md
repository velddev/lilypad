<img src="assets/logo.svg" width="96" alt="">

# Lilypad

Screenshots and screen recordings for niri on Wayland. Pick a region on a frozen screen by clicking a
detected UI element or dragging your own, draw on it first, and get a corner toast with the result.
Everything stays on disk; nothing is uploaded.

    lilypad screen            whole focused monitor
    lilypad region            pick a region on a frozen screen
    lilypad window            click a window
    lilypad record            start a region recording, or stop the running one

The top of `bin/lilypad` lists every command. Screenshots go to `~/Pictures/Screenshots` and
recordings to `~/Videos/Screen Recordings`.

## Install

Needs niri, quickshell, python, grim, imagemagick, wl-clipboard, ffmpeg and gpu-screen-recorder.
slurp is the fallback picker, satty the editor. Then build the region detector and link the command:

    ./build.sh
    ln -s "$PWD/bin/lilypad" ~/.local/bin/lilypad

Bind it in niri:

    Ctrl+Shift+3     { spawn "lilypad" "screen"; }
    Ctrl+Shift+4     { spawn "lilypad" "region"; }
    Ctrl+Shift+Alt+4 { spawn "lilypad" "window"; }

The first capture starts the UI (`qs -p shell`) and it stays running. To change the accent colour, put
`{"accent": "#89B4FA"}` in `~/.config/lilypad/accent.json`.

## Status file

`$XDG_RUNTIME_DIR/lilypad/status.json` says what a bar needs to show a recording:
`{"recording": true, "since": <ms since the epoch>, "canDraw": true, "drawing": false}`. Stop with
`lilypad record` and toggle drawing with `lilypad draw`.

## Layout

- `bin/lilypad`: the command, in Python
- `shell/`: the Quickshell UI, with the selector, editor, toolbar, overlay and toast in `capture/`
- `src/lilypad-regions.c`: finds rectangular UI elements in a screenshot. `./build.sh` builds it into `bin/`
