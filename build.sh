#!/usr/bin/env bash
# Builds src/lilypad-regions.c into bin/lilypad-regions. The binary isn't tracked. It parses image files,
# so it gets Arch's makepkg hardening.
set -euo pipefail
repo=$(cd "$(dirname "$0")" && pwd)
cc -O2 -Wall -Wextra -fstack-protector-strong -fstack-clash-protection -fcf-protection \
  -D_FORTIFY_SOURCE=3 -Wl,-z,relro,-z,now -Wl,--as-needed \
  -o "$repo/bin/lilypad-regions" "$repo/src/lilypad-regions.c"
