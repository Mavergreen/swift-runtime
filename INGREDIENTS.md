# Build ingredients

Everything baked into what this repo publishes, and how a change to it reaches a release. An
*ingredient* is an input to the product; the *own upstream* is the thing this repo exists to port.

This repo is unusual in the family twice over: it publishes a **build environment** for
`Mavergreen/swift-runtime` rather than an end-user `.pkg`, and it consumes **none** of
shipyard's CMake *modules* — no `CMakeLists.txt` of its own, no `find_package(MavericksShipyard)`,
no updater, no `.pkg`, no 10.9 install floor, so nothing to stage or sign. It does build and gate
with **`shipyard-cmake`**: the `lib/cmake/llvm/*.cmake` files inside the shipped tarball are the
product, `swift-runtime` consumes them with `shipyard-cmake`, and generating them with a different
CMake than the one that reads them is exactly the mismatch this repo exists to prevent. It still
runs the family conventions gate, because conventions that only apply to the typical repo are not
conventions.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Swift release (own upstream) | `SWIFT_VERSION` + `SWIFT_SHA` in `pins.env` | ✅ `github-tags` on `swiftlang/swift`, **patch automerged** | auto-cuts `<upstream>-mavericks.1` on the push to main (no tag to push by hand) |
| swiftlang/llvm-project commit | `LLVM_BRANCH` + `LLVM_SHA` in `pins.env` | ✅ `git-refs` | auto-repackages `-mavericks.(N+1)`; `LLVM_BRANCH` is `swift/release/<minor>` and must follow a minor Swift bump |
| swift.org toolchain `.pkg` | `TOOLCHAIN_URL`, derived from `SWIFT_VERSION` | ✅ moves with the Swift pin | verified by **signer identity**, not a hash — see below |

Not ingredients: the build scripts are this repo's recipe; a change there is a repackage you cut
deliberately (dispatch `release.yml` with `local_release=true`). There is no committed `VERSION` —
the packaging revision N is derived from the shipped tags.

## How a bump reaches a release

Both paths are automatic, and they are kept apart by *which pin moved*:

- **`SWIFT_VERSION` moved** → a new upstream. `version.sh` reports `RELEASE=yes` because that upstream
  has no tag yet, so the push to main auto-cuts `-mavericks.1`.
- **any other pin in `pins.env` moved** → an ingredient bump. `repackage-on-ingredient-bump.yml`
  dispatches `release.yml` with `local_release=true`, which cuts `-mavericks.(N+1)`.

The caller declares `own-upstream-paths: pins.env:SWIFT_VERSION` — a *key*, not a path, because both
kinds of pin live in the same file. Without that, a Swift bump would publish twice: once from the
push, once from the dispatched repackage.

## Why version and commit are captured by one regex

`SWIFT_VERSION` and `SWIFT_SHA` are matched by a single `matchStrings` so Renovate moves them together.
`verify-relocatable.sh` asserts the clone of `SWIFT_TAG` is exactly `SWIFT_SHA`, so a version bumped
without its commit **fails closed** rather than silently building something else.

## Why the toolchain is verified by signature, not a pinned hash

A hash can only vouch for bytes someone has already seen, so every version bump needed a human to paste
a new one — the one thing keeping Swift updates off the automated path. The signing identity is stable
across releases, so `TOOLCHAIN_SIGNER` verifies a version that does not exist yet. Upstream publishes no
GPG signature for the macOS `.pkg`; it is an Apple-signed installer, so `pkgutil` is the check that
exists.

## No repackage-on-ingredient-bump caller here

The pins above are all *own upstream* (the Swift release and the LLVM commit coupled to it), which is
the `-mavericks.1` path, not a repackage. There is no foreign ingredient to watch — this repo consumes
no other Mavergreen product. Add a caller the day one lands, with `own-upstream-paths: pins.env`.

## Conformance deviations

`check-artifact-conformance.sh` holds a release's artifacts to the family's schemes. These departures
are deliberate, and scoped to the artifact they concern:

- version:upstream-swift-*.pkg: mirrored verbatim from swift.org, so its version is upstream's own
  (`6.3.3.20260625101`). Rewriting it would break the correspondence with download.swift.org that this
  repo exists to keep checkable.
- floor:upstream-swift-*.pkg: upstream ships a 10.11 floor. We do not restamp a mirrored package.
- identifier:upstream-swift-*.pkg: `org.swift.*` is upstream's identifier; claiming
  `dev.mavergreen.*` for bytes we did not build would be a lie.
- install-path:Library/Developer/Toolchains/swift-*.xctoolchain/*: upstream's pkg, verbatim, installs where Xcode finds toolchains.
  It is its component's `install-location`, and where `xcrun --toolchain` looks; we do not relocate
  bytes we mirror.
- bundle-id:org.swift.*: upstream's own bundles, verbatim in upstream's pkg (sourcekitd, sourcekitdInProc, PlaygroundLogger).
- bundle-id:com.apple.dt.*: PlaygroundSupport and XCPlayground frameworks, verbatim in upstream's pkg under Apple's ids.
- bundle-id:com.apple.LLDB.framework: LLDB.framework, verbatim in upstream's pkg under Apple's id.
- bundle-id:SwiftBuild.*: SwiftPM's SwiftBuild_*.bundle resource bundles, verbatim in upstream's pkg.
- bundle-id:swift-crypto.*: SwiftPM's swift-crypto_*.bundle resource bundles, verbatim in upstream's pkg.

The `install-path` and `bundle-id` entries were read from upstream's 6.3.3 package itself (its
`PackageInfo`, `Distribution` and `Bom`, fetched by byte range rather than as the whole 1.4 GB); a
Swift release that adds a bundle under a new identifier will fail conformance until it is declared
here, which is the point.

The build-support tarball this repo *does* build carries no such exemption, which is the point of
scoping each deviation to a filename glob rather than to the check.
