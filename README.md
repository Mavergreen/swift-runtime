# swift

A **Swift runtime built from source for OS X 10.9 "Mavericks"** (Intel x86_64).

Modern Swift (6.x) assumes an Objective-C runtime and Swift ABI machinery that first shipped in
macOS 10.14.4. `mavericks-swift` builds `libswiftCore` from unmodified
[swiftlang/swift](https://github.com/swiftlang/swift) sources with a **10.9 deployment target**,
plus a small set of source patches that make Swift's class-realization path work on 10.9's
objc4-532 runtime. The result is **memory-safe on real hardware**: the validation test runs
**510/510 consecutive** clean on macOS 10.9.5, verified under Guard Malloc and MallocScribble.

This is Increment 0 (the core runtime) of a larger roadmap.

## What works

A memory-safe Swift **core runtime**: strings, arrays, dictionaries, sets, closures, generics,
existentials/protocol witnesses, ARC (incl. `weak`/`unowned`), class hierarchies, `NSObject`
subclasses, runtime-instantiated generic classes (the storage behind `Dictionary`/`Set`/`String`),
and `if #available`. Enough for **command-line / computational Swift**.

## Scope / bounds — read before using

- **Intel x86_64, OS X 10.9 only.**
- **Core runtime only.** Ships `libswiftCore` (+ `libswiftSwiftOnoneSupport` for `-Onone`). The
  Foundation / AppKit *overlays* — needed for most apps, and for GUI — are later roadmap increments.
- **Framework ceiling untouched.** Swift running does not bring back APIs absent from 10.9 (modern
  WKWebView, CryptoKit, Network.framework, …). Those are separate work.
- **Compilation happens on a modern host** cross-targeting `x86_64-apple-macosx10.9`. This is a
  *runtime*, not a native toolchain.
- Running on an OS with no security updates is your own risk.

## Install

```sh
sudo installer -pkg swift-runtime-<version>.pkg -target /
```
Installs the runtime into `/usr/local/mavergreen/swift-runtime/lib/swift/` and its license into
`/usr/local/mavergreen/swift-runtime/share/doc/`. A program finds the runtime through an rpath
naming that directory.

**Building a program for 10.9 on a modern Mac.** Use the swift.org toolchain of the Swift release
this runtime is built from, with the SDK `xcrun` finds. (On an Apple-silicon Mac, the `swiftc` in
Command Line Tools 27 cannot link this target: its `libswiftCompatibility*.a` are arm64-only.)
`swiftc` adds an rpath of `/usr/lib/swift`; replace it with the runtime's:
```sh
<swift.org toolchain>/usr/bin/swiftc -sdk "$(xcrun --show-sdk-path)" \
  -target x86_64-apple-macosx10.9 -O -no-stdlib-rpath \
  -Xlinker -rpath -Xlinker /usr/local/mavergreen/swift-runtime/lib/swift hello.swift -o hello
```
The binary's only rpath is the runtime's directory, so it runs on the 10.9 Mac, not on the one that
built it: copy `hello` to the 10.9 Mac and run `./hello` there.

**A prebuilt Swift binary** that expects the runtime in `/usr/lib/swift` needs one
[Drydock](https://github.com/Mavergreen/drydock) statement, usually beside others it already needs to
run on 10.9:
```
rpath replace /usr/lib/swift /usr/local/mavergreen/swift-runtime/lib/swift
```

## How it's built

`./build.sh` on a modern macOS: fetch the pinned swift.org toolchain, check out pinned Swift +
llvm-project sources, apply `patches/`, build the standard library only (no full LLVM), and
self-check with the compat guard. CI does the same on a `macos-26` runner and attaches the `.pkg`
to a GitHub Release (see `.github/workflows/release.yml`).

### The fix stack (all confirmed on real 10.9.5)

1. **Threading** — `SWIFT_THREADING_PACKAGE="OSX:pthreads"` removes `os_unfair_lock` (10.12).
2. **`-fno-sized-deallocation`** — 10.9's libc++ lacks the C++14 sized `operator delete`.
3. **`os_system_version` guard** — guarded + CoreFoundation `SystemVersion.plist` fallback, so
   `if #available` works on 10.9.
4. **`objc_readClassPair` guard + minimal in-place realization** — 10.9's objc lacks the 10.11 SPI;
   the runtime realizes runtime-instantiated generic classes itself, in objc4-532's layout.
5. **Realization-aware `getROData`** — follow `rw->ro` when `RW_REALIZED` (objc-532 realizes
   eagerly at image load, so the class's `Data` word is the `rw`, not the `ro`).
6. **objc-super instance-size fix** — size subclasses from `class_getInstanceSize(super)` on 10.9,
   where objc-532 drops the Swift is-swift bit and the normal path under-sizes them.

All gated to the pre-`objc_readClassPair` (10.9/10.10) runtime; the modern-OS code path is
byte-unchanged.

## Validation

The gate is on **real 10.9.5** (a modern host is structurally blind to these bugs):
`./make-selftest.sh` builds `tests/*.swift` at `-O` and `-Onone` into a bundle, and on the 10.9 box
`./run-selftest.sh --gate` requires 500 consecutive clean exits per binary, then 10 more under Guard
Malloc + MallocScribble + MallocGuardEdges, with no DYLD variables otherwise.

## Licensing

Swift is **Apache License 2.0 with the Runtime Library Exception** (see `LICENSE`). `mavericks-swift`
builds that source and redistributes the resulting binary under those terms — it does **not**
redistribute any Apple prebuilt runtime, SDK, or framework. See `NOTICE` for attribution and the
list of local patches. This repo's own glue (scripts, packaging) is under the same license.

## Provenance

Every release ships a `MANIFEST` with the exact Swift version, source commit SHAs, build flags, and
per-file `sha256`. No Apple bytes are committed here.
