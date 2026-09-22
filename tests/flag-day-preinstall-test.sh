#!/bin/sh
# The flag-day preinstall (scripts/pkg/preinstall) against a fake target volume: it removes the
# /LICENSE.txt pre-flag-day pkgs stray-installed ONLY when that file is provably ours, forgets the old
# receipt on that volume only, and never fails the install. pkgutil is a PATH stub with a fake
# receipt database, so nothing here touches a real one.
# DELETABLE with scripts/pkg/preinstall (shipyard SKILL.md "Consolidation backlog").
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
t="$(mktemp -d "${TMPDIR:-/tmp}/flagday.XXXXXX")"
trap 'rm -rf "$t"' EXIT
fail() { echo "FAIL: $*"; exit 1; }
OLD=dev.modernmavericks.swift-runtime

# The stub keeps one receipt: $t/receipt holds its file list; --forget deletes it, as pkgutil would,
# so a preinstall that forgets BEFORE it consults the receipt sees nothing and keeps the stray file.
mkdir -p "$t/bin"
cat > "$t/bin/pkgutil" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$t/pkgutil.log"
[ -z "\${PKGUTIL_FAIL:-}" ] || exit 1
case "\$*" in
  "--volume "*" --files $OLD") [ -f "$t/receipt" ] && cat "$t/receipt" ;;
  "--volume "*" --forget $OLD") [ -f "$t/receipt" ] && rm -f "$t/receipt" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$t/bin/pkgutil"

# The pkg's scripts dir, as package.sh assembles it: the preinstall plus the license it compares to.
mkdir -p "$t/scr"
cp "$ROOT/scripts/pkg/preinstall" "$t/scr/preinstall"; chmod +x "$t/scr/preinstall"
cp "$ROOT/LICENSE" "$t/scr/LICENSE.txt"

# A fresh volume with the pre-flag-day install on it.
setup() {
  rm -rf "$t/vol" "$t/pkgutil.log"; mkdir -p "$t/vol/usr/lib/swift"
  cp "$ROOT/LICENSE" "$t/vol/LICENSE.txt"
  printf 'LICENSE.txt\nusr\nusr/lib\nusr/lib/swift\nusr/lib/swift/libswiftCore.dylib\n' > "$t/receipt"
}
run() { PATH="$t/bin:$PATH" "$t/scr/preinstall" /x.pkg / "$t/vol" / || fail "preinstall exited non-zero"; }

# Ours (listed by the old receipt, identical bytes): removed, and the receipt forgotten on THIS volume.
setup; run
[ ! -e "$t/vol/LICENSE.txt" ] || fail "our stray /LICENSE.txt survived"
grep -qx -- "--volume $t/vol --forget $OLD" "$t/pkgutil.log" || fail "old receipt not forgotten on the target volume: $(cat "$t/pkgutil.log")"

# Same name, different bytes: someone else's file. Kept.
setup; echo "not ours" > "$t/vol/LICENSE.txt"; run
[ "$(cat "$t/vol/LICENSE.txt")" = "not ours" ] || fail "removed a /LICENSE.txt whose content is not ours"

# Identical bytes but the old receipt does not claim it (or there is no old receipt): kept.
setup; rm -f "$t/receipt"; run
[ -f "$t/vol/LICENSE.txt" ] || fail "removed a /LICENSE.txt no receipt of ours claims"

# A symlink named LICENSE.txt pointing at an identical file: not what we installed. Kept.
setup; rm -f "$t/vol/LICENSE.txt"; ln -s "$t/scr/LICENSE.txt" "$t/vol/LICENSE.txt"; run
[ -L "$t/vol/LICENSE.txt" ] || fail "removed a symlink at /LICENSE.txt"

# pkgutil failing outright (a box with no receipt database to speak of): nothing removed, exit 0.
setup; PATH="$t/bin:$PATH" PKGUTIL_FAIL=1 "$t/scr/preinstall" /x.pkg / "$t/vol" / || fail "a failing pkgutil failed the install"
[ -f "$t/vol/LICENSE.txt" ] || fail "removed /LICENSE.txt without the receipt vouching for it"

# No target volume: nothing is known about where an old install lives, so nothing is done.
setup; PATH="$t/bin:$PATH" "$t/scr/preinstall" || fail "preinstall with no args failed"
[ ! -f "$t/pkgutil.log" ] || fail "pkgutil ran with no target volume"

# package.sh ships it, with the license beside it -- and the license no longer at the payload root.
grep -q 'cp scripts/pkg/preinstall "$SCR/preinstall"' "$ROOT/package.sh" || fail "package.sh does not ship the preinstall"
grep -q 'cp "$LICENSE_TXT" "$SCR/LICENSE.txt"' "$ROOT/package.sh" || fail "package.sh does not ship the license beside the preinstall"
if grep -q '^cp .*"$OUT/LICENSE.txt"' "$ROOT/build.sh"; then fail "build.sh stages the license at the payload root again"; fi
echo "OK: flag-day preinstall"
