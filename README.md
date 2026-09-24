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
sudo installer -pkg mavericks-swift-<version>.pkg -target /
```
Installs `libswiftCore.dylib` into `/usr/lib/swift/`. Build consumers for
`x86_64-apple-macosx10.9` with an **absolute** rpath of `/usr/lib/swift` (10.9's dyld does not
honor `@loader_path`):
```sh
swiftc -target x86_64-apple-macosx10.9 -O -Xlinker -rpath -Xlinker /usr/lib/swift hello.swift -o hello
./hello
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

The gate is on **real 10.9.5** (a modern host is structurally blind to these bugs): the test binary
must pass **100× consecutive `exit 0` + Guard Malloc + MallocScribble clean**, with no DYLD
environment variables. See `tests/thorough_test.swift`.

## Licensing

Swift is **Apache License 2.0 with the Runtime Library Exception** (see `LICENSE`). `mavericks-swift`
builds that source and redistributes the resulting binary under those terms — it does **not**
redistribute any Apple prebuilt runtime, SDK, or framework. See `NOTICE` for attribution and the
list of local patches. This repo's own glue (scripts, packaging) is under the same license.

## Provenance

Every release ships a `MANIFEST` with the exact Swift version, source commit SHAs, build flags, and
per-file `sha256`. No Apple bytes are committed here.
