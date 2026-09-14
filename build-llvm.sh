#!/bin/sh
# build-llvm.sh — build a RELOCATABLE LLVM build-support tree for the Swift stdlib build.
#
# Produces out/llvm: a CMake *install* tree (relocatable — LLVMConfig.cmake derives its prefix
# from its own location) rather than a build tree (absolute paths baked in at configure time).
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/pins.env"
. "$HERE/msc.sh"   # -> $SHIPYARD (shipyard scripts dir)
# Scratch defaults to ./work (what CI uses). Override when the repo lives on slow or
# quirky storage -- e.g. this project's checkout is NFS-backed, where an LLVM build is
# slow and `rm -rf` races silly-rename. CI leaves this unset.
ROOT="${SWIFT_TOOLCHAIN_WORK:-$HERE/work}"; mkdir -p "$ROOT"; cd "$ROOT"
OUT="$HERE/out/llvm"

echo "==> 1. pinned llvm-project source (fetched BY SHA via shared clone_pinned.sh)"
# clone_pinned fetches the pinned commit DIRECTLY (not a branch tip): the moment swiftlang advances
# swift/release/6.3, a --branch clone stops containing $LLVM_SHA and this repo can never build again.
# Guard on llvm/ existing, not on .git -- an interrupted checkout leaves a .git whose HEAD passes the
# SHA test while the worktree is empty (cmake then dies confusingly), so re-fetch from scratch then.
if [ ! -d llvm-project/llvm ]; then
  rm -rf llvm-project
  sh "$SHIPYARD/clone_pinned.sh" https://github.com/swiftlang/llvm-project.git "$LLVM_BRANCH" "$LLVM_SHA" llvm-project
fi
test "$(git -C llvm-project rev-parse HEAD)" = "$LLVM_SHA" || {
  echo "FAIL: llvm-project SHA mismatch (want $LLVM_SHA)"; exit 1; }
[ -d llvm-project/llvm ] || { echo "FAIL: llvm-project checkout incomplete"; exit 1; }

echo "==> 2. configure + build TableGen only (libswiftCore does not link LLVM)"
# spec: 2026-09-13 shipyard CMake flag day -- the .cmake files installed in step 3 ARE the shipped
#       product, and swift-runtime's build.sh consumes them with shipyard-cmake. Generating them
#       with one CMake and consuming them with another is the mismatch this repo exists to prevent,
#       so the same pinned shipyard-cmake writes them.
if [ ! -x llvm-build/bin/llvm-tblgen ]; then
  shipyard-cmake -G Ninja -S llvm-project/llvm -B llvm-build \
    -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang \
    -DLLVM_TARGETS_TO_BUILD="X86;AArch64" \
    -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF
  # llvm-min-tblgen is named explicitly: step 3 copies it, and relying on it appearing
  # transitively would break the copy if a future LLVM stops pulling it in.
  ninja -C llvm-build llvm-tblgen llvm-min-tblgen clang-tblgen llvm-config \
        intrinsics_gen clang-tablegen-targets
fi

echo "==> 3. install the relocatable subset"
rm -rf "$OUT"; mkdir -p "$OUT"
for c in cmake-exports llvm-headers clang-cmake-exports clang-headers; do
  shipyard-cmake --install llvm-build --prefix "$OUT" --component "$c"
done
mkdir -p "$OUT/bin"
for b in llvm-tblgen clang-tblgen llvm-config llvm-min-tblgen; do
  cp "llvm-build/bin/$b" "$OUT/bin/$b"
done

echo "==> 4. relocatability fixups"
# (a) Neutralize the import-existence check. We ship the CMake package WITHOUT LLVM's static
#     archives: only TableGen is built, and SWIFT_INCLUDE_TOOLS=OFF means nothing links LLVM.
#     Without this, find_package(LLVM) aborts on libLLVMDemangle.a.
for f in "$OUT/lib/cmake/llvm/LLVMExports.cmake" "$OUT/lib/cmake/clang/ClangTargets.cmake"; do
  [ -f "$f" ] || continue
  /usr/bin/sed -i '' \
    's|^# Loop over all imported files and verify that they actually exist|set(_cmake_import_check_targets "")  # ModernMavericks: no LLVM archives shipped (nothing links them)\n&|' \
    "$f"
  grep -q 'ModernMavericks: no LLVM archives shipped' "$f" || {
    echo "FAIL: import-check neutralization did not apply to $f"; exit 1; }
done
# (b) LLVM_DEFAULT_EXTERNAL_LIT is the one remaining absolute build path. lit is unused
#     (SWIFT_INCLUDE_TESTS=OFF) and it would trip the no-absolute-paths assertion below.
/usr/bin/sed -i '' 's|^set(LLVM_DEFAULT_EXTERNAL_LIT .*|set(LLVM_DEFAULT_EXTERNAL_LIT "")|' \
  "$OUT/lib/cmake/llvm/LLVMConfig.cmake"

echo "==> 5. assert relocatability"
# No path from THIS build may survive in any shipped .cmake file.
if grep -rlF "$ROOT" "$OUT" --include='*.cmake' 2>/dev/null | grep .; then
  echo "FAIL: absolute build paths leaked into the install tree (listed above)"; exit 1
fi
grep -q 'set(LLVM_CMAKE_DIR "${LLVM_INSTALL_PREFIX}/lib/cmake/llvm")' \
  "$OUT/lib/cmake/llvm/LLVMConfig.cmake" || {
  echo "FAIL: LLVM_CMAKE_DIR is not prefix-relative — this is a build tree, not an install tree"
  exit 1; }
[ -f "$OUT/lib/cmake/llvm/LLVMInstallSymlink.cmake" ] || {
  echo "FAIL: LLVMInstallSymlink.cmake missing (Swift's SwiftComponents.cmake:203 needs it)"
  exit 1; }

echo "OK: relocatable LLVM build-support tree at $OUT ($(du -sh "$OUT" | cut -f1))"
