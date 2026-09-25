#!/bin/sh
# platform: host-agnostic
# Write UPSTREAM_VERSION = SWIFT_VERSION, the Swift release this runtime is built from (build.sh).
#
# Reads the pin with sed rather than sourcing build.sh: build.sh is the whole build, not a pins file.
# Same shape as swift-toolchain's, which reads its pins.env the same way and for the same reason.
#
# UPSTREAM_VERSION is build-derived and gitignored; VERSION (the full <upstream>-mavericks.N) derives
# from it plus the shipped tags.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SELF/.." && pwd)"

UP=$(sed -n 's/^SWIFT_VERSION="\([^"]*\)".*/\1/p' "$ROOT/build.sh" | head -1)
case "$UP" in
  [0-9]*.[0-9]*.[0-9]*) : ;;
  *) echo "derive-upstream-version: no sane SWIFT_VERSION in build.sh (got '$UP')" >&2; exit 1 ;;
esac

printf '%s\n' "$UP" > "$ROOT/UPSTREAM_VERSION"
printf '%s\n' "$UP"
