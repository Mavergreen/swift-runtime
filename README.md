# swift-toolchain

Host build environment for [Mavergreen/swift-runtime](https://github.com/Mavergreen/swift-runtime).

`swift`'s runtime is built from source against a pinned swiftlang LLVM. Building that LLVM
inside the consumer's CI was slow (~8 min), cache-dependent, and — because a CMake *build tree*
bakes absolute paths — silently broke whenever the checkout path changed. This repo builds it
once per pin and publishes a **relocatable** CMake *install* tree instead.

## Assets (per release)

| Asset | Size | What |
| --- | --- | --- |
| `swift-toolchain-<VERSION>-macos-<arch>.tar.gz` | ~13 MB | LLVM CMake package + headers + TableGen |
| `upstream-swift-<ver>-RELEASE-osx.pkg` | ~1.5 GB | Verbatim swift.org toolchain mirror |

## Scripts

    ./build-llvm.sh          # -> out/llvm  (relocatable install tree)
    ./mirror-toolchain.sh    # -> dist/upstream-swift-<ver>-RELEASE-osx.pkg
    ./package.sh             # -> dist/*.tar.gz + dist/SHA256SUMS
    ./verify-relocatable.sh  # the gate: relocate, then configure AND build swiftCore

## The gate

`verify-relocatable.sh` extracts the artifact into a directory whose name differs from where it
was built, then runs a full Swift stdlib-only configure and `ninja swiftCore-macosx-x86_64`
against it, asserting the result reports `minOS 10.9`. A build tree fails this; an install tree
passes. This is the regression that motivated the repo.

## Later

The 10.9 cross-toolchain lands here as an additional asset in the same release.
