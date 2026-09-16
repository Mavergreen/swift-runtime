#!/bin/sh
# Package $OUT (from build.sh) into a distributable .pkg.
# pkgbuild -> flat component pkg, then the SHARED set_install_floor.sh helper
# (mavericks-shipyard) wraps it with a 10.9.5 install floor + self-checks it.
#
# NOTE: trackpad2's BundleIsVersionChecked dance does NOT apply -- that guards *bundle*
# components; our payload is a plain libswiftCore.dylib (a file), always installed.
set -eu

OUT="${OUT:-$PWD/out}"
DIST="${DIST:-$PWD/dist}"
# The full version: reuses VERSION if the workflow already resolved it this run, else derives it
# from UPSTREAM_VERSION + the shipped tags. Never a committed file.
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/UPSTREAM_VERSION" ] || sh "$HERE/scripts/derive-upstream-version.sh" >/dev/null
. "$HERE/msc.sh"        # -> $SHIPYARD: resolve-version, stage_updater and set_install_floor
VERSION="$(MAVERICKS_ROOT="$HERE" sh "$SHIPYARD/resolve-version.sh")"
IDENTIFIER="${PKG_IDENTIFIER:-dev.modernmavericks.swift-runtime}"
NAME="swift-runtime-${VERSION}"
mkdir -p "$DIST"
[ -f "$OUT/usr/lib/swift/libswiftCore.dylib" ] || { echo "no build in $OUT; run build.sh" >&2; exit 1; }

echo ">> resources (welcome + license shown at install)"
RES="$DIST/resources"; mkdir -p "$RES"
cp scripts/resources/Welcome.html "$RES/"
[ -f "$OUT/LICENSE.txt" ] && cp "$OUT/LICENSE.txt" "$RES/" || echo "   (no LICENSE.txt in OUT; build.sh should vendor it)"

echo ">> stage updater app + LaunchAgent + postinstall into the payload (if built)"
UPD_APP="${UPD_APP:-$PWD/build/updater/SwiftUpdater.app}"
set --                                    # pkgbuild gets --scripts only when there IS a postinstall
if [ -d "$UPD_APP" ]; then
  SCR="$DIST/pkg-scripts"; rm -rf "$SCR"; mkdir -p "$SCR"
  sh "$SHIPYARD/stage_updater.sh" \
    --stage "$OUT" \
    --app "$UPD_APP" \
    --app-dir "/Library/Application Support/ModernMavericks" \
    --agent-label dev.modernmavericks.swift-updatecheck \
    --scripts-out "$SCR"
  set -- --scripts "$SCR"
else
  echo "   (no updater app at $UPD_APP; packaging runtime only -- build it: shipyard-cmake --build build/updater)"
fi

echo ">> flat component pkg (payload -> /usr/lib/swift, /usr/local, /Library/LaunchAgents)"
pkgbuild --root "$OUT" --identifier "$IDENTIFIER" --version "$VERSION" \
  "$@" \
  --install-location / "$DIST/swift-runtime-component.pkg"

echo ">> product archive with 10.9.5 floor (shared helper)"
sh "$SHIPYARD/set_install_floor.sh" \
  --identifier "$IDENTIFIER" \
  --title "Mavericks Swift Runtime — Swift core runtime for OS X 10.9" \
  --component "$DIST/swift-runtime-component.pkg" \
  --out "$DIST/${NAME}.pkg" \
  --resources "$RES" --welcome Welcome.html --license LICENSE.txt --host-arch x86_64

# The component pkg is an intermediate (no 10.9.5 OS floor -- installing it directly would bypass the
# gate). Only the product archive ships; drop the intermediate so it can't leak into the release glob.
rm -f "$DIST/swift-runtime-component.pkg"

echo ">> checksums"
( cd "$DIST" && shasum -a 256 "${NAME}.pkg" > SHA256SUMS )
cat "$DIST/SHA256SUMS"
echo "OK -> $DIST/${NAME}.pkg"
