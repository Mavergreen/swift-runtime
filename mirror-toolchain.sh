#!/bin/sh
# platform: macOS-only -- verifies the installer signature with pkgutil (lib.sh)
# mirror-toolchain.sh — download the official swift.org toolchain VERBATIM into the build cache and
# verify its signer. No repacking: the file is byte-identical to upstream, so its SHA256 is upstream's
# and provenance stays checkable against download.swift.org. build.sh expands it (it is the host
# compiler that builds the stdlib); release.yml attaches it to -mavericks.1 releases.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/pins.env"
. "$HERE/lib.sh"   # -> $SWIFT_BUILD
CACHE="$SWIFT_BUILD/cache"; mkdir -p "$CACHE"
PKG="$CACHE/$TOOLCHAIN_ASSET"

if [ ! -f "$PKG" ]; then
  echo "==> downloading $TOOLCHAIN_URL (~1.5 GB)"
  curl -fSL --retry 3 --retry-delay 5 -o "$PKG.tmp" "$TOOLCHAIN_URL"
  mv "$PKG.tmp" "$PKG"
fi

verify_toolchain_signature "$PKG" || { rm -f "$PKG"; exit 1; }
echo "OK: swift.org toolchain at $PKG"
