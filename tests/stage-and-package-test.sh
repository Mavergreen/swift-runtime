#!/bin/sh
# usage: sh tests/stage-and-package-test.sh   (from the repo root, as run-repo-tests.sh runs it)
#   Stages a fake build with scripts/stage-runtime.sh, packages it with package.sh, and checks the
#   payload is exactly the runtime prefix and passes artifact conformance with no deviation.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
command -v pkgbuild >/dev/null 2>&1 || { echo "no pkgbuild (not macOS) -- skipping"; exit 77; }
. "$REPO/msc.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f scripts/stage-runtime.sh ] || fail "no scripts/stage-runtime.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/stage-and-package.XXXXXX")"
trap 'rm -rf "$T"' EXIT
P=usr/local/mavergreen-swift-runtime

mkdir -p "$T/built"
printf 'int f(void){return 0;}\n' > "$T/f.c"
for lib in libswiftCore libswiftSwiftOnoneSupport; do
  cc -dynamiclib -arch x86_64 -mmacosx-version-min=10.9 -install_name "@rpath/$lib.dylib" \
    -o "$T/built/$lib.dylib" "$T/f.c"
done

echo "-- staging refuses a build with no libswiftSwiftOnoneSupport.dylib"
mkdir -p "$T/partial"; cp "$T/built/libswiftCore.dylib" "$T/partial/"
if sh scripts/stage-runtime.sh "$T/partial" "$T/out-partial" LICENSE 2> "$T/partial.err"; then
  fail "stage-runtime.sh succeeded without libswiftSwiftOnoneSupport.dylib"
fi
grep -q 'has no libswiftSwiftOnoneSupport.dylib' "$T/partial.err" \
  || fail "stage-runtime.sh failed, but not for the missing dylib: $(cat "$T/partial.err")"

echo "-- staging refuses an empty out-dir before writing anything"
# Every command that writes is faked (and fails), so a regressed guard fails this test instead of
# deleting /usr or writing into a writable /usr/local.
mkdir -p "$T/fakebin"
for c in rm mkdir cp mv ln chmod; do
  printf '#!/bin/sh\necho "%s $*" >> "%s/writes.log"\nexit 1\n' "$c" "$T" > "$T/fakebin/$c"; chmod +x "$T/fakebin/$c"
done
if PATH="$T/fakebin:$PATH" sh scripts/stage-runtime.sh "$T/built" "" LICENSE 2>/dev/null; then
  fail "stage-runtime.sh accepted an empty out-dir"
fi
[ ! -f "$T/writes.log" ] || fail "stage-runtime.sh tried to write, with an empty out-dir: $(cat "$T/writes.log")"

echo "-- package.sh refuses an OUT that has only the old /usr/lib/swift layout"
mkdir -p "$T/old/usr/lib/swift"; cp "$T/built/libswiftCore.dylib" "$T/old/usr/lib/swift/"
if OUT="$T/old" DIST="$T/dist-old" UPD_APP=/nonexistent sh ./package.sh > "$T/old.log" 2>&1; then
  fail "package.sh packaged an OUT with no $P"
fi
grep -q 'run build.sh' "$T/old.log" || fail "package.sh refused, but without saying to run build.sh"

echo "-- staging replaces whatever an earlier layout left in OUT"
mkdir -p "$T/out/usr/lib/swift" "$T/out/usr/local/share/doc/mavericks-swift-runtime" "$T/out/Library/keep"
: > "$T/out/usr/lib/swift/libswiftCore.dylib"
: > "$T/out/usr/local/share/doc/mavericks-swift-runtime/LICENSE.txt"
: > "$T/out/LICENSE.txt"
sh scripts/stage-runtime.sh "$T/built" "$T/out" LICENSE
got="$(cd "$T/out" && find usr LICENSE.txt Library 2>/dev/null | sort)"
want="$(printf '%s\n' Library Library/keep usr usr/local "$P" "$P/LICENSE.txt" "$P/lib" "$P/lib/swift" \
  "$P/lib/swift/libswiftCore.dylib" "$P/lib/swift/libswiftSwiftOnoneSupport.dylib" | sort)"
[ "$got" = "$want" ] || fail "staged tree is
$got
wanted
$want"
cmp -s LICENSE "$T/out/$P/LICENSE.txt" || fail "staged LICENSE.txt is not this repo's LICENSE"

echo "-- package.sh packages exactly the prefix"
rm -rf "$T/out/Library"
OUT="$T/out" DIST="$T/dist" UPD_APP=/nonexistent sh ./package.sh > "$T/pkg.log" 2>&1 \
  || { cat "$T/pkg.log" >&2; fail "package.sh failed on the staged layout"; }
pkg="$(ls "$T/dist"/swift-runtime-*.pkg)"
# platform: a pkg built on a macOS 27 host whose files carry com.apple.provenance lists AppleDouble
#           ._* members for them; CI-built pkgs have none, and 10.9's installer lays down no ._ file.
payload="$(pkgutil --payload-files "$pkg" | grep -v '/\._' | sort)"
want_payload="$(printf '%s\n' . ./usr ./usr/local "./$P" "./$P/LICENSE.txt" "./$P/lib" "./$P/lib/swift" \
  "./$P/lib/swift/libswiftCore.dylib" "./$P/lib/swift/libswiftSwiftOnoneSupport.dylib" | sort)"
[ "$payload" = "$want_payload" ] || fail "payload is
$payload
wanted
$want_payload"

echo "-- the pkg passes artifact conformance with no install-path deviation declared"
if grep -q '^- install-path:' INGREDIENTS.md; then fail "INGREDIENTS.md still declares an install-path deviation"; fi
version="$(basename "$pkg" .pkg)"; version="${version#swift-runtime-}"
facts="$(sh "$SHIPYARD/artifact-facts.sh" "$T/dist" "$version")" || fail "artifact-facts.sh failed"
[ -n "$facts" ] || fail "artifact-facts.sh printed nothing"
printf '%s\n' "$facts" | sh "$SHIPYARD/check-artifact-conformance.sh" || fail "artifact conformance failed"
echo "PASS"
