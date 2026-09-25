#!/bin/sh
#   usage: make-selftest.sh
#          Compiles every tests/*.swift for x86_64-apple-macosx10.9, at -O and -Onone, into a
#          self-test bundle for a 10.9 box: bin/<name> and bin/<name>-Onone, plus run-selftest.sh.
#          Each binary's only rpath is $SWIFT_RUNTIME_PREFIX/lib/swift (default
#          /usr/local/mavergreen/swift-runtime), so the bundle exercises exactly the runtime there.
#          Run after build.sh, which expands the toolchain this uses. Prints the tarball's path last.
#          Env: MAVERICKS_BUILD_ROOT, TC (toolchain usr/), DIST (output dir), SWIFT_RUNTIME_PREFIX.
set -eu
REPO="$(cd "$(dirname "$0")" && pwd)"
: "${MAVERICKS_BUILD_ROOT:=${TMPDIR:-/tmp}/mm-build}"
SWRT_BUILD="$MAVERICKS_BUILD_ROOT/swift-runtime-cross"
TC="${TC:-$SWRT_BUILD/work/toolchain/usr}"
DIST="${DIST:-$SWRT_BUILD/dist}"
RUNTIME_LIB="${SWIFT_RUNTIME_PREFIX:-/usr/local/mavergreen/swift-runtime}/lib/swift"
SWIFTC="$TC/bin/swiftc"
[ -x "$SWIFTC" ] || { echo "make-selftest: no swiftc at $SWIFTC -- run build.sh first" >&2; exit 1; }
SDK="$(xcrun --show-sdk-path)"

NAME=swift-runtime-selftest
B="$DIST/$NAME"; rm -rf "$B"; mkdir -p "$B/bin"
for src in "$REPO"/tests/*.swift; do
  [ -f "$src" ] || continue
  n="$(basename "$src" .swift)"
  for opt in O Onone; do
    out="$B/bin/$n"; [ "$opt" = O ] || out="$B/bin/$n-$opt"
    "$SWIFTC" -sdk "$SDK" -target x86_64-apple-macosx10.9 "-$opt" -no-stdlib-rpath \
      -Xlinker -rpath -Xlinker "$RUNTIME_LIB" "$src" -o "$out" >&2
    echo "built: $(basename "$out")" >&2
  done
done
[ -n "$(ls -A "$B/bin")" ] || { echo "make-selftest: no tests/*.swift to build" >&2; exit 1; }
cp "$REPO/tests/run-selftest.sh" "$B/run-selftest.sh"; chmod +x "$B/run-selftest.sh"

# A modern host's bsdtar tags most files with com.apple.provenance and packs it as a pax
# LIBARCHIVE.xattr./SCHILY.xattr. header; 10.9's libarchive 2.8.3 can't parse that ("Ignoring
# malformed pax extended attribute") and `tar -xzf` there exits 1. COPYFILE_DISABLE keeps
# AppleDouble ._ sidecar members out of the archive too. --no-xattrs suppresses the pax header, but
# 10.9's own bsdtar (this script also runs ON 10.9) doesn't know that flag and would abort under
# set -eu, so probe for support first instead of passing it unconditionally.
NOX=""
if tar --no-xattrs -cf /dev/null "$REPO/make-selftest.sh" >/dev/null 2>&1; then NOX="--no-xattrs"; fi
( cd "$DIST" && COPYFILE_DISABLE=1 tar $NOX -czf "$NAME.tar.gz" "$NAME" && rm -rf "$NAME" )
echo "$DIST/$NAME.tar.gz"
