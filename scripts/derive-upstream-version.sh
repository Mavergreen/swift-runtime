#!/bin/sh
# platform: host-agnostic
# Write UPSTREAM_VERSION = SWIFT_VERSION, the ONE authoritative Swift pin in pins.env.
#
# Reads the one pin with sed; pins.env is pins-only (tests/pins-test.sh), so sourcing it would also
# work, but this script needs nothing else from it.
#
# So there is still exactly one place to bump Swift -- pins.env's SWIFT_VERSION, which Renovate
# manages -- and UPSTREAM_VERSION follows it automatically. It is build-derived and gitignored;
# VERSION derives from it plus the shipped tags.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SELF/.." && pwd)"

UP=$(sed -n 's/^SWIFT_VERSION="\([^"]*\)".*/\1/p' "$ROOT/pins.env" | head -1)
case "$UP" in
  [0-9]*.[0-9]*.[0-9]*) : ;;
  *) echo "derive-upstream-version: no sane SWIFT_VERSION in pins.env (got '$UP')" >&2; exit 1 ;;
esac

printf '%s\n' "$UP" > "$ROOT/UPSTREAM_VERSION"
printf '%s\n' "$UP"
