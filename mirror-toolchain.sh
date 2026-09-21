#!/bin/sh
# mirror-toolchain.sh — download the official swift.org toolchain and stage it VERBATIM.
# No repacking: the mirrored file is byte-identical to upstream, so its SHA256 is the upstream
# SHA256 and provenance stays checkable against download.swift.org. That digest is RECORDED, not
# pinned -- the gate is the installer signature (see lib.sh), which holds across releases.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/pins.env"
. "$HERE/lib.sh"   # -> $STC_BUILD (out-of-tree build root)
DIST="$STC_BUILD/dist"; mkdir -p "$DIST"
PKG="$DIST/$TOOLCHAIN_ASSET"

if [ ! -f "$PKG" ]; then
  echo "==> downloading $TOOLCHAIN_URL (~1.5 GB)"
  curl -fSL --retry 3 --retry-delay 5 -o "$PKG.tmp" "$TOOLCHAIN_URL"
  mv "$PKG.tmp" "$PKG"
fi

verify_toolchain_signature "$PKG" || { rm -f "$PKG"; exit 1; }
echo "OK: verbatim toolchain mirror at $PKG"
