#!/bin/sh
# platform: macOS-only -- runs xcrun
# verify-relocatable.sh — THE GATE.
#
# Extracts out/llvm into a directory whose name differs from where it was built, then runs a
# full Swift stdlib-only configure AND build against it, asserting minOS 10.9. A CMake build
# tree fails this (absolute paths); an install tree passes. This is the regression that
# motivated this repo -- do not weaken it to a configure-only check.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/pins.env"
. "$HERE/msc.sh"   # -> $SHIPYARD (shipyard scripts dir)
. "$HERE/lib.sh"    # -> $STC_BUILD (out-of-tree build root)
# Same scratch override as build-llvm.sh. This gate does a full Swift stdlib build, so it
# especially wants local disk when the repo is on slow storage. CI leaves this unset.
ROOT="${SWIFT_TOOLCHAIN_WORK:-$STC_BUILD/work}"; mkdir -p "$ROOT"; cd "$ROOT"
DI="$(xcrun -f dyld_info)"

[ -d "$STC_BUILD/out/llvm" ] || { echo "FAIL: run ./build-llvm.sh first"; exit 1; }

echo "==> 1. toolchain (host swiftc/clang)"
if [ ! -x toolchain/usr/bin/swiftc ]; then
  PKG="$STC_BUILD/dist/$TOOLCHAIN_ASSET"
  [ -f "$PKG" ] || { echo "FAIL: run ./mirror-toolchain.sh first (need $PKG)"; exit 1; }
  rm -rf tc-expand toolchain; mkdir -p toolchain
  pkgutil --expand "$PKG" tc-expand
  ditto -x -z "$(find tc-expand -name Payload | head -1)" toolchain
  rm -rf tc-expand
fi
TC="$ROOT/toolchain/usr"

echo "==> 2. pinned swift source (unpatched: we are testing the ENVIRONMENT, not the patches)"
[ -d swift ] || sh "$SHIPYARD/clone_pinned.sh" https://github.com/swiftlang/swift.git "$SWIFT_TAG" "$SWIFT_SHA" swift
test "$(git -C swift rev-parse HEAD)" = "$SWIFT_SHA" || {
  echo "FAIL: swift SHA mismatch (want $SWIFT_SHA)"; exit 1; }

echo "==> 3. RELOCATE: unpack the SHIPPED TARBALL under a name that differs from the build location"
# Deliberately extract dist/*.tar.gz, not out/llvm: the gate must test the bytes we publish,
# not the directory they were staged from.
TARBALL="$STC_BUILD/dist/$BUILDSUPPORT_ASSET"
[ -f "$TARBALL" ] || { echo "FAIL: run ./package.sh first (need $TARBALL)"; exit 1; }
rm -rf gate-relocated gate-build
mkdir -p gate-relocated
tar -C gate-relocated -xzf "$TARBALL"
R="$ROOT/gate-relocated/llvm"

echo "==> 4. configure Swift stdlib-only against the RELOCATED tree"
# spec: 2026-09-13 shipyard CMake flag day -- swift-runtime's build.sh configures the stdlib with
#       shipyard-cmake, and this gate is the rehearsal of that. Configuring it with any other cmake
#       would stop testing what the consumer actually does.
shipyard-cmake -G Ninja -S swift -B gate-build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$TC/bin/clang" -DCMAKE_CXX_COMPILER="$TC/bin/clang++" \
  -DLLVM_DIR="$R/lib/cmake/llvm" \
  -DLLVM_BUILD_LIBRARY_DIR="$R/lib" \
  -DLLVM_BUILD_BINARY_DIR="$R/bin" \
  -DLLVM_BUILD_MAIN_SRC_DIR="$R" \
  -DSWIFT_INCLUDE_TOOLS=OFF \
  -DSWIFT_BUILD_STDLIB=ON -DSWIFT_BUILD_DYNAMIC_STDLIB=ON -DSWIFT_BUILD_STATIC_STDLIB=OFF \
  -DSWIFT_BUILD_SDK_OVERLAY=OFF -DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=OFF \
  -DSWIFT_BUILD_STATIC_SDK_OVERLAY=OFF \
  -DSWIFT_BUILD_REMOTE_MIRROR=OFF -DSWIFT_BUILD_SOURCEKIT=OFF -DSWIFT_BUILD_SWIFT_SYNTAX=OFF \
  -DSWIFT_INCLUDE_TESTS=OFF -DSWIFT_INCLUDE_DOCS=OFF \
  -DSWIFT_BUILD_PERF_TESTSUITE=OFF \
  -DSWIFT_SDKS="OSX" \
  -DSWIFT_HOST_VARIANT_SDK=OSX -DSWIFT_HOST_VARIANT_ARCH="$(uname -m)" \
  -DSWIFT_PRIMARY_VARIANT_SDK=OSX -DSWIFT_PRIMARY_VARIANT_ARCH="$ARCH" \
  -DSWIFT_DARWIN_SUPPORTED_ARCHS="$ARCH" \
  -DSWIFT_DARWIN_DEPLOYMENT_VERSION_OSX="$DEPLOYMENT" \
  -DSWIFT_THREADING_PACKAGE="OSX:pthreads" \
  -DSWIFT_NATIVE_SWIFT_TOOLS_PATH="$TC/bin" -DSWIFT_NATIVE_CLANG_TOOLS_PATH="$TC/bin" \
  -DSWIFT_EXPERIMENTAL_EXTRA_FLAGS="-Xfrontend;-disable-availability-checking"

echo "==> 5. BUILD swiftCore against the relocated tree"
ninja -C gate-build "swiftCore-macosx-$ARCH"

echo "==> 6. assert the result is a 10.9 x86_64 runtime"
CORE="$ROOT/gate-build/lib/swift/macosx/$ARCH/libswiftCore.dylib"
[ -f "$CORE" ] || { echo "FAIL: no libswiftCore.dylib produced"; exit 1; }
PLATFORM_OUT="$("$DI" -platform "$CORE")"
printf '%s\n' "$PLATFORM_OUT" | sed -n '3,4p'
MINOS="$(printf '%s\n' "$PLATFORM_OUT" | awk 'NR==4{print $2}')"
[ "$MINOS" = "$DEPLOYMENT" ] || {
  echo "FAIL: built runtime is not minOS $DEPLOYMENT (got: $MINOS)"; exit 1; }

echo "OK: relocated build-support tree configures AND builds a minOS $DEPLOYMENT $ARCH libswiftCore"
