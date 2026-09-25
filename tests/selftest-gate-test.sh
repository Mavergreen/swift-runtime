#!/bin/sh
# platform: macOS-only -- builds Mach-O fixtures with -dynamiclib and loads libgmalloc.dylib
# usage: sh tests/selftest-gate-test.sh
#   Exercises tests/run-selftest.sh against small C fixtures: a clean program, one that exits 1,
#   and one whose heap overrun only Guard Malloc catches.
set -eu
REPO="$(cd "$(dirname "$0")/.." && pwd)"
command -v cc >/dev/null 2>&1 || { echo "no cc -- skipping"; exit 77; }
[ -f /usr/lib/libgmalloc.dylib ] || { echo "no /usr/lib/libgmalloc.dylib -- skipping"; exit 77; }

T="$(mktemp -d "${TMPDIR:-/tmp}/selftest-gate.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

printf 'int main(void){return 0;}\n' > "$T/ok.c"
printf 'int main(void){return 1;}\n' > "$T/bad.c"
printf '#include <stdlib.h>\nint main(void){char *p=malloc(16); volatile char c=p[16]; (void)c; free(p); return 0;}\n' > "$T/overrun.c"
printf 'int f(void){return 0;}\n' > "$T/notgm.c"
cc -o "$T/ok" "$T/ok.c"; cc -o "$T/bad" "$T/bad.c"; cc -O0 -o "$T/overrun" "$T/overrun.c"
cc -dynamiclib -o "$T/notgmalloc.dylib" "$T/notgm.c"
mkdir -p "$T/prefix/lib/swift"; : > "$T/prefix/lib/swift/libswiftCore.dylib"

bundle() {  # $1.. = fixtures to put in a fresh bundle's bin/; prints the bundle dir
  b="$(mktemp -d "$T/bundle.XXXXXX")"; mkdir -p "$b/bin"
  cp "$REPO/tests/run-selftest.sh" "$b/"
  for f in "$@"; do cp "$T/$f" "$b/bin/"; done
  printf '%s\n' "$b"
}
RUNS=3
run() {  # $1 = bundle, rest = args; runs from / so the script must find its own bin/; sets rc, out
  b="$1"; shift
  rc=0; out="$(cd / && SWIFT_RUNTIME_PREFIX="$T/prefix" SELFTEST_RUNS="$RUNS" sh "$b/run-selftest.sh" "$@" 2>&1)" || rc=$?
}

echo "-- no runtime installed at the prefix: SKIP"
b="$(bundle ok)"; rc=0; out="$(SWIFT_RUNTIME_PREFIX="$T/nowhere" sh "$b/run-selftest.sh" 2>&1)" || rc=$?
[ "$rc" = 77 ] || fail "expected 77 with no runtime, got $rc: $out"

echo "-- quick mode, all pass"
run "$(bundle ok)"; [ "$rc" = 0 ] || fail "quick ok: rc=$rc: $out"
case "$out" in *'ALL PASS'*) ;; *) fail "quick ok: no ALL PASS: $out" ;; esac

echo "-- gate, all pass (and Guard Malloc confirmed)"
run "$(bundle ok)" --gate; [ "$rc" = 0 ] || fail "gate ok: rc=$rc: $out"

echo "-- gate, one test exits 1"
run "$(bundle ok bad)" --gate; [ "$rc" = 1 ] || fail "gate bad: rc=$rc: $out"
case "$out" in *'FAIL: bad'*) ;; *) fail "gate bad: failure not named: $out" ;; esac

echo "-- an overrun passes quick mode but the gate catches it under Guard Malloc"
run "$(bundle overrun)"; [ "$rc" = 0 ] || fail "quick overrun should pass: rc=$rc: $out"
run "$(bundle overrun)" --gate; [ "$rc" = 1 ] || fail "gate overrun: rc=$rc: $out"
case "$out" in *'Guard Malloc run'*) ;; *) fail "gate overrun: not attributed to Guard Malloc: $out" ;; esac

echo "-- a Guard Malloc that does not load fails the gate"
b="$(bundle ok)"; rc=0
out="$(SWIFT_RUNTIME_PREFIX="$T/prefix" SELFTEST_RUNS=2 SELFTEST_GMALLOC="$T/notgmalloc.dylib" sh "$b/run-selftest.sh" --gate 2>&1)" || rc=$?
[ "$rc" = 1 ] || fail "non-gmalloc insert: rc=$rc: $out"
case "$out" in *'Guard Malloc did not load'*) ;; *) fail "non-gmalloc insert: wrong reason: $out" ;; esac

echo "-- an empty bin/ fails"
run "$(bundle)"; [ "$rc" = 1 ] || fail "empty bin: rc=$rc: $out"

echo "-- no bin/ at all (the repo's own tests/, as run-repo-tests.sh runs it): SKIP"
b="$(mktemp -d "$T/bundle.XXXXXX")"; cp "$REPO/tests/run-selftest.sh" "$b/"
run "$b"; [ "$rc" = 77 ] || fail "no bin/: rc=$rc: $out"
case "$out" in *'not a self-test bundle (no bin/)'*) ;; *) fail "no bin/: wrong reason: $out" ;; esac

echo "-- a non-numeric SELFTEST_RUNS is refused"
RUNS=abc; run "$(bundle ok)" --gate; RUNS=3
[ "$rc" = 1 ] || fail "SELFTEST_RUNS=abc: rc=$rc: $out"
case "$out" in *'SELFTEST_RUNS'*) ;; *) fail "SELFTEST_RUNS=abc: not named: $out" ;; esac

echo "-- an unknown argument is refused, not run as quick mode"
run "$(bundle ok)" -gate; [ "$rc" = 2 ] || fail "-gate: rc=$rc: $out"
case "$out" in *'usage: run-selftest.sh [--gate]'*) ;; *) fail "-gate: no usage line: $out" ;; esac

echo "-- an inherited DYLD_* variable is refused"
# platform: modern macOS's SIP strips DYLD_* from the environment of /bin/sh itself, so the
#           refusal is observable only where a DYLD_ variable reaches a sh child (10.9: no SIP).
if [ "$(DYLD_LIBRARY_PATH=/x sh -c 'printf %s "${DYLD_LIBRARY_PATH:-}"')" = /x ]; then
  b="$(bundle ok)"; rc=0
  out="$(cd / && DYLD_LIBRARY_PATH="$T/nowhere" SWIFT_RUNTIME_PREFIX="$T/prefix" SELFTEST_RUNS="$RUNS" \
    sh "$b/run-selftest.sh" --gate 2>&1)" || rc=$?
  [ "$rc" = 1 ] || fail "DYLD_LIBRARY_PATH set: rc=$rc: $out"
  case "$out" in
    *'refusing to run with DYLD_* set: DYLD_LIBRARY_PATH'*) ;;
    *) fail "DYLD_LIBRARY_PATH set: wrong reason: $out" ;;
  esac
else
  echo "   DYLD_* stripped by this OS; refusal case not exercised"
fi
echo "PASS"
