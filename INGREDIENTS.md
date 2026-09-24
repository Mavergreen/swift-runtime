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
| Swift release (own upstream) | `SWIFT_VERSION` + `SWIFT_SHA` in `pins.env` | ✅ `github-tags` on `swiftlang/swift`, grouped with llvm-project into one "Swift release" PR, ship-if-green | auto-cuts `<upstream>-mavericks.1` on the push to main (no tag to push by hand) |
| swiftlang/llvm-project commit | `LLVM_SWIFT_RELEASE` + `LLVM_SHA` in `pins.env` | ✅ `github-tags` on `swiftlang/llvm-project`, in the same "Swift release" PR | moves only WITH the Swift pin: `build-llvm.sh` fails unless `LLVM_SWIFT_RELEASE` equals `SWIFT_VERSION` and `LLVM_SHA` is llvm-project's `swift-<SWIFT_VERSION>-RELEASE` |
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
without its commit **fails closed** rather than silently building something else. `LLVM_SWIFT_RELEASE`
and `LLVM_SHA` are captured the same way, for the same reason.

## Why LLVM is pinned by release tag, and checked against the Swift pin

LLVM build support cut for one Swift release and used for another **builds fine and is wrong** — the
one failure a green build cannot catch. It used to be a branch pin (`swift/release/<minor>`) tracked
by `git-refs`, which can only follow the tip of the branch it names: through 6.3 that happened to
cover every patch release, but from 6.4 swiftlang cuts a branch per release (`swift/release/6.4.0`,
`6.4.1`, …), so a Swift patch bump would have automerged against the previous release's LLVM.

llvm-project tags every Swift release with the same `swift-X.Y.Z-RELEASE` name swiftlang/swift uses
(all 18 Swift 6 releases, checked 2026-09-24), so LLVM is now pinned by that tag. Its release is its
own literal, `LLVM_SWIFT_RELEASE`, rather than derived from `SWIFT_VERSION` — a deliberate repeat,
because Renovate needs a value of its own to move `LLVM_SHA` by, and two managers capturing one
literal would both rewrite it. The repeat cannot drift silently: `build-llvm.sh` refuses to start
unless the two are equal and `LLVM_SHA` is the commit llvm-project's tag names. The two pins are
grouped into one Renovate PR; apart, each would fail that check and neither could merge. With a
mismatch unbuildable, a minor Swift bump needs no human either: it builds and ships like a patch.

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
  (`6.4.20260913101` for 6.4.0). Rewriting it would break the correspondence with download.swift.org that this
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
- bundle-id:swift-build.*: SwiftPM's SwiftBuild_*.bundle resource bundles, verbatim in upstream's pkg (6.4 renamed their ids from `SwiftBuild.*`).
- bundle-id:swiftpm.*: SwiftPM's own SwiftPM_*.bundle resource bundles (SBOMModel), verbatim in upstream's pkg.
- bundle-id:swift-crypto.*: SwiftPM's swift-crypto_*.bundle resource bundles, verbatim in upstream's pkg.

The `install-path` and `bundle-id` entries were read from upstream's 6.3.3 package itself (its
`PackageInfo`, `Distribution` and `Bom`, fetched by byte range rather than as the whole 1.4 GB), and
re-read from 6.4.0's with `artifact-facts.sh` when that release renamed and added bundles; a
Swift release that adds a bundle under a new identifier will fail conformance until it is declared
here, which is the point.

The build-support tarball this repo *does* build carries no such exemption, which is the point of
scoping each deviation to a filename glob rather than to the check.
