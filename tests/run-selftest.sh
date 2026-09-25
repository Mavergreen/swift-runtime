#!/bin/sh
# platform: macOS-only -- runs the installed runtime's Mach-O tests, and Guard Malloc is libgmalloc.dylib
#   usage: run-selftest.sh [--gate]
#          Validates the Swift runtime INSTALLED on this Mac (OS X 10.9) by running every bin/* test,
#          which were built with an rpath of $SWIFT_RUNTIME_PREFIX/lib/swift (make-selftest.sh).
#            (default)  each test once
#            --gate     the acceptance bar: SELFTEST_RUNS consecutive clean exits (default 500),
#                       then 10 runs under Guard Malloc + MallocScribble + MallocGuardEdges
#          SWIFT_RUNTIME_PREFIX  default /usr/local/mavergreen/swift-runtime; must match the rpath the
#                                tests were built with
#          SELFTEST_GMALLOC      default /usr/lib/libgmalloc.dylib
#          Exit 0 all pass, 1 any failure or any DYLD_* variable set, 2 any other argument, 77 no
#          runtime installed (the family SKIP code: a CI runner never has one) or no bin/ here (the
#          repo's own tests/, which is not a bundle).
set -eu
cd "$(dirname "$0")"
# Anything else once ran quick mode: a mistyped -gate printed ALL PASS as if it had gated.
case "$#:${1:-}" in
  0:|1:--gate) ;;
  *) echo "usage: run-selftest.sh [--gate]" >&2; exit 2 ;;
esac

PREFIX="${SWIFT_RUNTIME_PREFIX:-/usr/local/mavergreen/swift-runtime}"
CORE="$PREFIX/lib/swift/libswiftCore.dylib"
GMALLOC="${SELFTEST_GMALLOC:-/usr/lib/libgmalloc.dylib}"
RUNS="${SELFTEST_RUNS:-500}"
GMALLOC_RUNS=10

[ -f "$CORE" ] || {
  echo "Swift runtime not found at $CORE" >&2
  echo "Install it first:  sudo installer -pkg swift-runtime-*.pkg -target /" >&2
  exit 77
}
# run-repo-tests.sh runs every tests/*.sh, this one included, from the repo's tests/, which is not a
# bundle; wherever a runtime is installed, "No tests in bin/" below failed the whole suite. A bin/
# that exists but is empty is a broken bundle, and still fails.
[ -d bin ] || { echo "not a self-test bundle (no bin/) -- skipping" >&2; exit 77; }
# The gate's rule is "no DYLD variables": DYLD_LIBRARY_PATH and its kin outrank the rpath, so the
# tests could validate some other runtime. (Guard Malloc's DYLD_INSERT_LIBRARIES below is set on
# each command, never inherited.)
dyld="$(env | sed -n 's/^\(DYLD_[A-Za-z0-9_]*\)=.*/\1/p' | tr '\n' ' ')"
[ -z "$dyld" ] || { echo "refusing to run with DYLD_* set: ${dyld% }" >&2; exit 1; }
case "$RUNS" in
  ''|*[!0-9]*|0) echo "SELFTEST_RUNS must be a positive integer (got '$RUNS')" >&2; exit 1 ;;
esac

MODE="${1:-quick}"
pass=0; fail=0; failed=""
for t in bin/*; do
  [ -f "$t" ] && [ -x "$t" ] || continue
  name="$(basename "$t")"; ok=1; why=""
  if [ "$MODE" = "--gate" ]; then
    n=0
    while [ "$n" -lt "$RUNS" ]; do
      "./$t" >/dev/null 2>&1 || { ok=0; why="run $((n + 1)) of $RUNS exited non-zero"; break; }
      n=$((n + 1))
    done
    g=0
    while [ "$ok" = 1 ] && [ "$g" -lt "$GMALLOC_RUNS" ]; do
      # libgmalloc announces itself on stderr ("GuardMalloc[pid]: ...") on 10.9 and on modern macOS
      # alike; its absence means the run was not guarded, which must not read as a pass.
      err="$(DYLD_INSERT_LIBRARIES="$GMALLOC" MallocScribble=1 MallocGuardEdges=1 "./$t" 2>&1 >/dev/null)" \
        || { ok=0; why="Guard Malloc run $((g + 1)) of $GMALLOC_RUNS exited non-zero"; break; }
      case "$err" in
        *'GuardMalloc['*) ;;
        *) ok=0; why="Guard Malloc did not load ($GMALLOC)"; break ;;
      esac
      g=$((g + 1))
    done
    label="${RUNS}x + ${GMALLOC_RUNS}x Guard Malloc"
  else
    "./$t" >/dev/null 2>&1 || { ok=0; why="exited non-zero"; }
    label="run"
  fi
  if [ "$ok" = 1 ]; then
    printf '  PASS (%s): %s\n' "$label" "$name"; pass=$((pass + 1))
  else
    printf '  FAIL: %s -- %s\n' "$name" "$why"; fail=$((fail + 1)); failed="$failed $name"
  fi
done

echo "----------------------------------------"
echo "passed=$pass  failed=$fail"
[ $((pass + fail)) -gt 0 ] || { echo "No tests in bin/ -- nothing was validated." >&2; exit 1; }
if [ "$fail" -eq 0 ]; then
  echo "ALL PASS -- the Swift runtime works on this machine."
else
  echo "FAILURES:$failed"
  echo "(Please report it with your exact OS X build: sw_vers.)"
  exit 1
fi
