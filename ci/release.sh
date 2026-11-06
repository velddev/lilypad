#!/bin/sh
# Packs the release for this machine's architecture into dist/. Runs in an Alpine container
# (.github/workflows/release.yml): the helper links statically against musl and zlib, so one
# tarball per architecture works on every distro.
set -eu
cd "$(dirname "$0")/.."
apk add --no-cache build-base zlib-dev zlib-static
./build.sh -static
strip bin/lilypad-regions
mkdir -p dist
tar -czf "dist/lilypad-$(uname -m).tar.gz" bin shell
