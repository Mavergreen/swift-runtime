#!/bin/sh
# build.sh — reproducible from-source build of libswiftCore for macOS 10.9 / x86_64.
#
# Produces: out/libswiftCore.dylib (+ libswiftSwiftOnoneSupport.dylib), minOS 10.9,
# from Swift 6.3.3 swift.org sources, with NO Apple prebuilt runtime bytes redistributed.
#
# Host: macOS with Xcode Command Line Tools (full Xcode NOT required), ninja + git, and the
# shipyard pkg (it provides shipyard-cmake, the only cmake this family configures with).
# Cross-target build (host may be arm64; output is x86_64). ~30-60 min from clean on 8 cores.
#
# Everything is PINNED below. Do not float versions — the stdlib is coupled to its compiler.
set -eu

# ---------------------------- PINNED INPUTS ----------------------------------
# The host build environment (swiftlang LLVM build support + the swift.org toolchain) is built
# and published by ModernMavericks/swift-toolchain. We fetch it by pinned URL + SHA256 rather
# than building LLVM here. A CMake *build tree* bakes absolute paths into LLVMConfig.cmake at
# configure time, so a build that reuses one is only correct while the checkout path never
# moves -- and this repo's rename proved it does. The published tree is a CMake *install* tree,
# which derives its prefix from its own location; nothing here depends on cache state.
TOOLCHAIN_REPO="ModernMavericks/swift-toolchain"
TOOLCHAIN_REF="6.3.3-mavericks.4"   # renovate: github-releases ModernMavericks/swift-toolchain
SWIFT_VERSION="6.3.3"   # renovate: swiftlang/swift
SWIFT_SHA="064859e41d68596f486c5d724401cb370f260409"          # commit at SWIFT_TAG; Renovate moves it with SWIFT_VERSION
# DERIVED from SWIFT_VERSION, never repeated: a Renovate bump rewrites one line, and a tag left
# behind would clone a different Swift than SWIFT_SHA names. (swift-toolchain's pins.env learned this
# the same way -- it used to repeat the version four times.)
SWIFT_TAG="swift-${SWIFT_VERSION}-RELEASE"
# Built by swift-toolchain, so it carries that repo's name and version; the -macos-arm64
# suffix names the machine that built the TableGen binaries inside it.
BUILDSUPPORT_ASSET="swift-toolchain-$TOOLCHAIN_REF-macos-arm64.tar.gz"
# A verbatim mirror of swift.org's installer, so it keeps upstream's filename -- that correspondence
# is what makes the mirror checkable.
TOOLCHAIN_ASSET="upstream-swift-$SWIFT_VERSION-RELEASE-osx.pkg"
DEPLOYMENT="10.9"
ARCH="x86_64"
# -----------------------------------------------------------------------------

HERE="$(cd "$(dirname "$0")" && pwd)"   # script dir (= repo root); capture BEFORE any cd, since $0
                                         # is relative when invoked as ./build.sh and we cd below.
# platform: a family checkout may live on NFS, where a build cost 11.16s wall / 25% CPU against
#           2.96s / 88% on local disk, identical user time -- the whole difference is I/O wait.
: "${MAVERICKS_BUILD_ROOT:=${TMPDIR:-/tmp}/mm-build}"
SWRT_BUILD="$MAVERICKS_BUILD_ROOT/swift-runtime-cross"
# Scratch defaults out of the source tree, onto $MAVERICKS_BUILD_ROOT (CI: $RUNNER_TEMP, local disk).
# SWIFT_RUNTIME_WORK still overrides directly -- e.g. to point AT the tree for a deliberate in-tree
# build, or elsewhere entirely when the checkout itself lives on slow storage (expanding the 4.6 GB
# toolchain payload there took hours; the difference is I/O wait, not CPU).
ROOT="${SWIFT_RUNTIME_WORK:-$SWRT_BUILD/work}"
mkdir -p "$ROOT"; cd "$ROOT"
SDK="$(xcrun --show-sdk-path)"
DI="/Library/Developer/CommandLineTools/usr/bin/dyld_info"

BASE="https://github.com/$TOOLCHAIN_REPO/releases/download/$TOOLCHAIN_REF"

# Verify against the release's OWN published SHA256SUMS, not hashes pasted in here. A pinned hash can
# only vouch for bytes someone has already seen, so every bump needed a human to fetch and paste two
# new ones -- the single thing that kept this repo's ingredients off the automated path. Both assets
# come from our own swift-toolchain release, and publish-release.yml regenerates SHA256SUMS over
# everything it attaches, so it covers exactly these files. (Same trust model container-tools uses
# for the golang toolchain.)
if [ ! -f SHA256SUMS ]; then
  curl -fSL --retry 3 --retry-delay 5 -o SHA256SUMS.tmp "$BASE/SHA256SUMS"
  mv SHA256SUMS.tmp SHA256SUMS
fi

fetch_verify() {   # $1 = asset filename; its expected hash comes from SHA256SUMS
  if [ ! -f "$1" ]; then
    curl -fSL --retry 3 --retry-delay 5 -o "$1.tmp" "$BASE/$1"
    mv "$1.tmp" "$1"
  fi
  # Fail if the asset is not LISTED, rather than passing an empty expectation to shasum: an asset
  # missing from SHA256SUMS is unverified, which must never look like a pass.
  line="$(grep -E "  $1\$" SHA256SUMS || true)"
  [ -n "$line" ] || { echo "FAIL: $1 is not listed in $TOOLCHAIN_REF's SHA256SUMS"; exit 1; }
  printf '%s\n' "$line" | shasum -a 256 -c - || { echo "FAIL: $1 SHA256 mismatch"; rm -f "$1"; exit 1; }
}

echo "==> 1. host build environment (published by $TOOLCHAIN_REPO @ $TOOLCHAIN_REF)"
fetch_verify "$BUILDSUPPORT_ASSET"
fetch_verify "$TOOLCHAIN_ASSET"

[ -d llvm/lib/cmake/llvm ] || { rm -rf llvm; tar -xzf "$BUILDSUPPORT_ASSET"; }
LLVMB="$ROOT/llvm"

if [ ! -x toolchain/usr/bin/swiftc ]; then
  rm -rf tc-expand toolchain; mkdir -p toolchain
  pkgutil --expand "$TOOLCHAIN_ASSET" tc-expand
  ditto -x -z "$(find tc-expand -name Payload | head -1)" toolchain
  rm -rf tc-expand
fi
TC="$ROOT/toolchain/usr"

echo "==> 2. sources (pinned)"
[ -d swift ] || git clone --depth 1 --branch "$SWIFT_TAG" https://github.com/swiftlang/swift.git swift
test "$(git -C swift rev-parse HEAD)" = "$SWIFT_SHA"        || { echo "swift SHA mismatch"; exit 1; }
# Defensive: some macOS checkouts fail `git apply` with iconv_open(UTF-8, UTF-8-MAC) on
# unicode paths. Harmless where not needed; prevents a runner-specific patch-apply failure.
git -C swift config core.precomposeunicode false

echo "==> 3. SOURCE PATCHES (six; all in ./patches, applied in order)"
#  0001 unsized operator delete  — 10.9's libc++ lacks __ZdlPvm (sized delete).
#       Safe: IRGen (the only consumer needing sized dealloc) isn't built here.
#  0002 os-version 10.9 fallback — guards os_system_version_get_current_version
#       (macOS 10.10, called unguarded by the availability backing) with a
#       CoreFoundation plist fallback so `if #available` works instead of aborting
#       under 10.9's dyld. Turns an unguarded weak import into a guarded one.
#  0003 guard objc_readClassPair (macOS 10.11) in swift_instantiateObjCClass AND
#       do the minimal in-place objc4-532 realization of runtime-instantiated
#       generic classes when it is absent (calloc class_rw_t, RW_REALIZED,
#       rw->ro=ro, empty cache/vtable, install into data_NEVER_USE) so the ObjC
#       runtime can read/message them on 10.9. (Replaces the earlier broken "skip".)
#  0004 realization-aware getROData — objc4-532 realizes classes eagerly at image
#       load, so a class's Data word may be a class_rw_t; follow rw->ro when
#       RW_REALIZED is set. Both overloads. Fixes garbage ro reads on 10.9.
#  0005 objc-super instance size — in initClassFieldOffsetVector, on the
#       readClassPair-absent (10.9/10.10) runtime, size a subclass from
#       class_getInstanceSize(super) when the objc-super branch would otherwise
#       under-size it (static Swift super's is-swift bit not observed on 10.9).
#  0007 is-swift mask legacy bit — SWIFT_CLASS_IS_SWIFT_MASK=1 for sub-10.14.4
#       Apple targets. The 6.3.3 compiler tags static classes with the LEGACY
#       is-swift bit (bit 0 / value 1) when targeting <10.14.4; a runtime that
#       hardcodes bit 1 (value 2) then reads every static Swift class as
#       isTypeMetadata()==false -> mangled reflection names, and is the root of
#       0005's superIsTypeMetadata==0. Confirmed safe on real 10.9.5 (pure-objc
#       classes leave data low bits free). This is the ROOT fix 0005 symptom-patched.
# Patches are --no-prefix format; apply with -p0.
PATCHES_DIR="$HERE/patches"
for p in "$PATCHES_DIR"/0001-*.patch "$PATCHES_DIR"/0002-*.patch "$PATCHES_DIR"/0003-*.patch \
         "$PATCHES_DIR"/0004-*.patch "$PATCHES_DIR"/0005-*.patch "$PATCHES_DIR"/0007-*.patch; do
  git -C swift apply -p0 --check "$p" && git -C swift apply -p0 "$p" || { echo "patch failed: $p"; exit 1; }
done
grep -q 'fno-sized-deallocation' swift/CMakeLists.txt || { echo "patch 0001 not applied"; exit 1; }
grep -q 'CFPropertyListCreateWithStream' swift/stdlib/public/stubs/Availability.mm || { echo "patch 0002 not applied"; exit 1; }
grep -q 'mav_minimalRealize' swift/stdlib/public/runtime/SwiftObject.mm || { echo "patch 0003 (realization) not applied"; exit 1; }
grep -q 'mav_roFromClassData' swift/stdlib/public/runtime/Metadata.cpp || { echo "patch 0004 (getROData) not applied"; exit 1; }
grep -q 'class_getInstanceSize((Class)const_cast' swift/stdlib/public/runtime/Metadata.cpp || { echo "patch 0005 (objc-super size) not applied"; exit 1; }
grep -q 'ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 101404' swift/include/swift/Runtime/Config.h || { echo "patch 0007 (is-swift mask) not applied"; exit 1; }
# de-instrumented: no debug logging must ship
! grep -rq 'getenv("MAV_' swift/stdlib/public/runtime/ || { echo "MAV debug logging leaked into patches"; exit 1; }

echo "==> 4. Swift STDLIB-ONLY configure (prebuilt toolchain as native tools)"
# LLVM_BUILD_* are build-tree-only variables that an install tree does not define, but
# SwiftSharedCMakeConfig.cmake preconditions on them. LLVM_BUILD_MAIN_SRC_DIR only needs to be
# set, never to exist: it feeds LLVM_MAIN_SRC_DIR, read solely by test/ and lib/Basic, both
# skipped under SWIFT_INCLUDE_TESTS=OFF / SWIFT_INCLUDE_TOOLS=OFF -- so no LLVM source is needed.
# Clang_DIR, LLVM_TABLEGEN and CLANG_TABLEGEN are deliberately absent: CMake reports them
# unused in this configuration, since the branch that would read them is behind SWIFT_INCLUDE_TOOLS.
shipyard-cmake -G Ninja -S swift -B "$ROOT/stdlib-build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER="$TC/bin/clang" -DCMAKE_CXX_COMPILER="$TC/bin/clang++" \
  -DLLVM_DIR="$LLVMB/lib/cmake/llvm" \
  -DLLVM_BUILD_LIBRARY_DIR="$LLVMB/lib" \
  -DLLVM_BUILD_BINARY_DIR="$LLVMB/bin" \
  -DLLVM_BUILD_MAIN_SRC_DIR="$LLVMB" \
  -DSWIFT_INCLUDE_TOOLS=OFF \
  -DSWIFT_BUILD_STDLIB=ON -DSWIFT_BUILD_DYNAMIC_STDLIB=ON -DSWIFT_BUILD_STATIC_STDLIB=OFF \
  -DSWIFT_BUILD_SDK_OVERLAY=OFF -DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=OFF -DSWIFT_BUILD_STATIC_SDK_OVERLAY=OFF \
  -DSWIFT_BUILD_REMOTE_MIRROR=OFF -DSWIFT_BUILD_SOURCEKIT=OFF -DSWIFT_BUILD_SWIFT_SYNTAX=OFF \
  -DSWIFT_INCLUDE_TESTS=OFF -DSWIFT_INCLUDE_DOCS=OFF \
  -DSWIFT_BUILD_PERF_TESTSUITE=OFF -DSWIFT_BUILD_EXAMPLES=OFF \
  -DSWIFT_SDKS="OSX" \
  -DSWIFT_HOST_VARIANT_SDK=OSX -DSWIFT_HOST_VARIANT_ARCH="$(uname -m)" \
  -DSWIFT_PRIMARY_VARIANT_SDK=OSX -DSWIFT_PRIMARY_VARIANT_ARCH="$ARCH" \
  -DSWIFT_DARWIN_SUPPORTED_ARCHS="$ARCH" \
  -DSWIFT_DARWIN_DEPLOYMENT_VERSION_OSX="$DEPLOYMENT" \
  -DSWIFT_THREADING_PACKAGE="OSX:pthreads" \
  -DSWIFT_NATIVE_SWIFT_TOOLS_PATH="$TC/bin" -DSWIFT_NATIVE_CLANG_TOOLS_PATH="$TC/bin" \
  -DSWIFT_EXPERIMENTAL_EXTRA_FLAGS="-Xfrontend;-disable-availability-checking"

echo "==> 5. build libswiftCore (+ SwiftOnoneSupport)"
ninja -C "$ROOT/stdlib-build" swiftCore-macosx-$ARCH swiftSwiftOnoneSupport-macosx-$ARCH

echo "==> 6. stage output (install layout: out/usr/lib/swift/ so package.sh's pkgbuild --root works)"
REPO="$HERE"
OUT="${SWIFT_RUNTIME_OUT:-$SWRT_BUILD/out}"; DEST="$OUT/usr/lib/swift"; mkdir -p "$DEST"
CORE="$DEST/libswiftCore.dylib"
cp "$ROOT/stdlib-build/lib/swift/macosx/$ARCH/libswiftCore.dylib" "$CORE"
cp "$ROOT/stdlib-build/lib/swift/macosx/$ARCH/libswiftSwiftOnoneSupport.dylib" "$DEST/" 2>/dev/null || true
# vendor the license into OUT so package.sh can show it at install time
cp "$REPO/LICENSE" "$OUT/LICENSE.txt"

echo "==> 7. self pre-flight (must show minOS 10.9 and NO os_unfair_lock)"
arch -x86_64 "$DI" -platform "$CORE" | sed -n '3,4p'
if arch -x86_64 "$DI" -imports "$CORE" | grep -q 'os_unfair_lock'; then
  echo "FAIL: os_unfair_lock still imported"; exit 1
fi
# objc_readClassPair must be present only as a *weak* import (guarded), never hard.
if arch -x86_64 "$DI" -imports "$CORE" | grep 'objc_readClassPair' | grep -qv '\[weak-import\]'; then
  echo "FAIL: objc_readClassPair is a HARD import"; exit 1
fi
# release build must carry no debug-logging leftovers.
if strings "$CORE" | grep -q 'MAV_'; then
  echo "FAIL: debug (MAV_) strings present in shipped dylib"; exit 1
fi
echo "OK: no os_unfair_lock; objc_readClassPair weak-guarded; no debug strings; staged in $OUT"
