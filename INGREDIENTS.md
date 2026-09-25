# Build ingredients

Everything baked into the shipped runtime `.pkg`, and how a change to it reaches a release.

| Ingredient | Pinned in | Renovate | On a bump |
|---|---|---|---|
| Swift version (own upstream) | `SWIFT_VERSION` + `SWIFT_SHA` in `build.sh` | ✅ `github-tags` on `swiftlang/swift`; minor/major held for a human | auto-cuts `<upstream>-mavericks.1` on the push to main |
| Mavergreen swift-toolchain build environment | `TOOLCHAIN_REF` in `build.sh` | ✅ `github-releases` | auto-repackages `-mavericks.(N+1)` |
| Source patches (`patches/`) | this repo | n/a | auto-repackages `-mavericks.(N+1)`: they change what ships |
| Sparkle framework, MacOSX10.9 SDK | `Mavergreen/shipyard@v1` | ✅ github-actions manager tracks the tag | `@v1` is a moving tag; no path changes, so nothing auto-repackages |

## Why there are no pinned SHA256s here any more

`BUILDSUPPORT_SHA256` and `TOOLCHAIN_SHA256` used to be pasted into `build.sh`. A hash can only vouch
for bytes someone has already seen, so every `TOOLCHAIN_REF` bump needed a human to download two
assets and paste two new hashes — which is why this pin sat at `6.3.3-mavericks.1` while
swift-toolchain had shipped `.3`.

Both assets come from our own swift-toolchain release, and `publish-release.yml` regenerates
`SHA256SUMS` over everything it attaches. So `build.sh` fetches that file and verifies against it:
the same bytes are checked (the first conversion was confirmed hash-for-hash against the old
literals), but a version that does not exist yet is covered too, leaving Renovate only the ref to
move. An asset **missing** from `SHA256SUMS` is a hard failure rather than an empty expectation
handed to `shasum` — unverified must never look like a pass.

`SWIFT_TAG` is likewise derived from `SWIFT_VERSION` rather than repeated, so a bump rewrites one
line and cannot leave a tag pointing at a different Swift than `SWIFT_SHA` names.

## How a bump reaches a release

Both paths are automatic, and they are kept apart by *which pin moved*:

- **`SWIFT_VERSION` moved** → a new upstream. `version.sh` reports `RELEASE=yes` because that upstream
  has no tag yet, so the push to main auto-cuts `-mavericks.1`.
- **`TOOLCHAIN_REF`, `BUILDSUPPORT_SHA256`, or anything under `patches/` moved** → an ingredient bump.
  `repackage-on-ingredient-bump.yml` dispatches `release.yml` with `local_release=true`, which cuts
  `-mavericks.(N+1)`.

The caller declares `own-upstream-paths: build.sh:SWIFT_VERSION` — a *key*, not a path, because both
kinds of pin live in the same file. Without it a Swift bump would publish twice: `-mavericks.1` from
the push and `-mavericks.2` from the dispatched repackage.

## Automatic publishing does not mean automatic acceptance

This is the one place where that distinction bites, and it is a deliberate choice rather than an
oversight. A macOS 26 runner is structurally blind to the 10.9-only behaviour this runtime exists to
fix — see the release-gating note at the top of `.github/workflows/release.yml`. So an auto-cut
release here **can reach a 10.9 user through Sparkle before anyone has run it on real hardware**.

The trade accepted: shipping promptly and letting real-hardware breakage surface as a follow-up
`-mavericks.(N+1)`, rather than holding every ingredient bump behind a manual validation step. If a
release turns out to be bad on 10.9, the fix is another repackage — the same remedy the rest of the
family uses, and the reason `N` exists.

What this does *not* change: CI green is still not acceptance. Real-10.9 validation remains the bar
for believing a release is good; it is no longer the bar for publishing one.

## Conformance deviations

- sdk-pin:*/swift-runtime/lib/swift/*.dylib: the Swift runtime cannot be built against the 10.9 SDK, which has no libc++ headers at all (only libstdc++ 4.2.1) while Swift 6.4 requires C++17, and which lacks declarations of post-10.9 APIs the runtime calls behind availability checks. Its build uses a modern SDK: today the CI runner's Xcode SDK, unpinned; the swift T2 decision (2026-09-25) replaces that with one pinned modern SDK used by CI and on 10.9. minos stays 10.9, and the real-10.9 gate is its acceptance. Revisit if the gate gains per-product pins.
