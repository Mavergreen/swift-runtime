#!/bin/sh
# package.sh — tar the LLVM build-support tree and emit dist/SHA256SUMS.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/pins.env"
. "$HERE/lib.sh"   # -> $STC_BUILD (out-of-tree build root)
DIST="$STC_BUILD/dist"; mkdir -p "$DIST"
[ -d "$STC_BUILD/out/llvm" ] || { echo "FAIL: run ./build-llvm.sh first"; exit 1; }

TARBALL="$DIST/$BUILDSUPPORT_ASSET"
PKG="$DIST/$TOOLCHAIN_ASSET"

echo "==> verifying toolchain pin before packaging"
[ -f "$PKG" ] || { echo "FAIL: run ./mirror-toolchain.sh first (need $PKG)"; exit 1; }
verify_toolchain_signature "$PKG" || exit 1

echo "==> packaging $TARBALL"
rm -f "$TARBALL"
# Archive the `llvm` directory itself so the consumer extracts to <root>/llvm.
# NOT byte-reproducible yet: gzip embeds an mtime and tar records per-file mtimes, so
# rebuilding from identical pins yields a different SHA256. Deliberately deferred rather
# than half-solved -- feeding bsdtar an explicit sorted file list (the usual fix) made it
# synthesize AppleDouble ._* members from extended attributes on this NFS checkout and blew
# the artifact from 13M to 64M; neither --no-mac-metadata nor COPYFILE_DISABLE suppressed
# it. Traversal mode handles the sidecars correctly. Revisit in CI, where the filesystem has
# no AppleDouble at all, and gate any change on BOTH the SHA being stable AND the size and
# entry count being unchanged.
tar -C "$STC_BUILD/out" -czf "$TARBALL" llvm

echo "==> SHA256SUMS"
( cd "$DIST" && shasum -a 256 "$BUILDSUPPORT_ASSET" "$TOOLCHAIN_ASSET" > SHA256SUMS )
cat "$DIST/SHA256SUMS"
echo "OK: assets staged in $DIST"
