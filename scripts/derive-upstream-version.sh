#!/bin/sh
# platform: host-agnostic
# Write UPSTREAM_VERSION = SWIFT_VERSION, the ONE authoritative Swift pin in pins.env.
#
# Reads the pin with sed rather than sourcing pins.env, deliberately: pins.env computes VERSION (the
# full <upstream>-mavericks.N), which is derived FROM this file. Sourcing it here would be circular.
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
