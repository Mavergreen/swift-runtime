#!/bin/sh
# platform: host-agnostic
# Print the URL of the release notes for one upstream Swift version. shipyard's
# upstream-notes.sh links it from our release notes when a release ships a NEW upstream.
#   usage: upstream-release-notes-url.sh <upstream-version>      (bare: 6.3.3)
# Swift publishes no notes for patch releases -- the swift-X-RELEASE GitHub release has an empty
# body -- so link the CHANGELOG as of that release tag, which is what a reader can actually read.
set -eu
printf 'https://github.com/swiftlang/swift/blob/swift-%s-RELEASE/CHANGELOG.md\n' "${1:?usage: upstream-release-notes-url.sh <upstream-version>}"
