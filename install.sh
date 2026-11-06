#!/bin/sh
# Installs Lilypad, or updates it if it's already there:
#
#   curl -fsSL https://lilypad.to | sh
#
# Clones it to ~/.local/share/lilypad, builds the region detector and links `lilypad` into
# ~/.local/bin. Anything else, it asks first: root is only for installing missing packages.
# Everything is in main, so a download cut off halfway runs nothing.
set -eu

# curl | sh makes the script our stdin, so answers come from the terminal. No terminal means no.
ask() {
  printf '%s [y/N] ' "$1" >&2
  answer=
  { read -r answer </dev/tty; } 2>/dev/null || true
  case $answer in
    [yY]*) return 0 ;;
    *) return 1 ;;
  esac
}

main() {
  repo=${LILYPAD_REPO:-https://github.com/velddev/lilypad.git}
  dir=${XDG_DATA_HOME:-$HOME/.local/share}/lilypad
  link=$HOME/.local/bin/lilypad

  # command:Arch package
  missing=
  for need in bash:bash git:git cc:gcc python3:python niri:niri qs:quickshell grim:grim \
      magick:imagemagick wl-copy:wl-clipboard ffmpeg:ffmpeg \
      gpu-screen-recorder:gpu-screen-recorder; do
    command -v "${need%%:*}" >/dev/null 2>&1 || missing="$missing ${need#*:}"
  done
  if [ -n "$missing" ]; then
    echo "Lilypad needs:$missing"
    if command -v pacman >/dev/null 2>&1; then
      ask "Install them with pacman?" || exit 1
      # shellcheck disable=SC2086
      sudo pacman -S --needed --noconfirm $missing </dev/tty
    else
      ask "Install them with your package manager first. Carry on anyway?" || exit 1
    fi
  fi

  if [ -e "$link" ] && [ ! -L "$link" ]; then
    ask "$link already exists. Replace it?" || exit 1
  fi

  if [ -d "$dir/.git" ]; then
    echo "Updating $dir"
    git -C "$dir" pull --quiet --ff-only
  else
    echo "Cloning into $dir"
    mkdir -p "$(dirname "$dir")"
    GIT_TERMINAL_PROMPT=0 git clone --quiet --depth 1 "$repo" "$dir"
  fi
  "$dir/build.sh"
  mkdir -p "$(dirname "$link")"
  ln -sfn "$dir/bin/lilypad" "$link"

  echo "Installed: $link"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "~/.local/bin isn't on your PATH, so add it to run lilypad from a terminal." ;;
  esac
  cat <<BINDS

Add these to the binds block of your niri config:

    Ctrl+Shift+3     { spawn "$link" "screen"; }
    Ctrl+Shift+4     { spawn "$link" "region"; }
    Ctrl+Shift+Alt+4 { spawn "$link" "window"; }
    Ctrl+Shift+5     { spawn "$link" "record"; }
BINDS
}

main
