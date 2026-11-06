#!/bin/sh
# Builds src/lilypad-regions.c into bin/lilypad-regions. The binary isn't tracked. It parses image files,
# so it gets Arch's makepkg hardening. Arguments go to the compiler: ci/release.sh passes -static.
set -eu
repo=$(cd "$(dirname "$0")" && pwd)
case $(uname -m) in
  x86_64) branches=-fcf-protection ;;
  aarch64) branches=-mbranch-protection=standard ;;
  *) branches= ;;
esac
# shellcheck disable=SC2086
cc -O2 -Wall -Wextra -fstack-protector-strong -fstack-clash-protection $branches \
  -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -Wl,-z,relro,-z,now -Wl,--as-needed "$@" \
  -o "$repo/bin/lilypad-regions" "$repo/src/lilypad-regions.c" -lz
