# Lilypad

Screenshots and screen recordings for niri on Wayland. Pick a region on a frozen screen by clicking a
detected UI element or dragging your own, draw on it first, and get a corner toast with the result.
Everything stays on disk; nothing is uploaded.

    pond-capture screen            whole focused monitor
    pond-capture region            pick a region on a frozen screen
    pond-capture window            click a window
    pond-capture record            start a region recording, or stop the running one

`pond-capture` with no arguments isn't useful; see the top of `bin/pond-capture` for every command.

## Layout

- `bin/pond-capture`: the command, in Python
- `shell/capture/`: the Quickshell UI (selector, editor, toolbar, overlay, toast)
- `shell/assets/`: the icons that UI loads
- `src/pond-regions.c`: finds rectangular UI elements in a screenshot. `./build.sh` builds it into `bin/`

## Status

Copied from [velddev/dotfiles](https://github.com/velddev/dotfiles) at `239998d`, where the running copy
still lives. It doesn't run on its own yet: `shell/capture/` is written to sit inside pond-shell and
imports its `PanelStyle`, `Theme`, `Accent`, `PopoverFade`, `Shadow` and `HoverAnimation`, and
`pond-capture` calls pond-shell over IPC. The names still say `pond-capture` and `pond-regions`.
