cmake_minimum_required(VERSION 3.16)
# Builds SwiftUpdater.app -- a Cocoa/Sparkle updater for the Swift runtime .pkg.
# It links NO libswiftCore (the runtime it updates), so there is no self-update circularity.
# This is the ONLY CMake in swift-runtime; the runtime itself is built by build.sh (swift.org source).
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.9 CACHE STRING "updater runs on 10.9")
set(CMAKE_OSX_ARCHITECTURES x86_64 CACHE STRING "Intel-only")
project(SwiftUpdater LANGUAGES OBJC)

find_package(MavericksShipyard REQUIRED)
include(Mavericks)          # universal umbrella: AppleClang gate + build conventions
include(MavericksSparkle)   # the Sparkle updater .app builder

# Derived, never committed: UPSTREAM_VERSION (written from build.sh's SWIFT_VERSION by
# scripts/derive-upstream-version.sh) plus the shipped tags decide it.
mavericks_resolve_version(MAVSWIFT_VERSION)

mavericks_add_updater_app(
  NAME SwiftUpdater
  PRODUCT_NAME "Mavericks Swift Runtime"
  BUNDLE_ID dev.mavergreen.SwiftUpdater
  FEED_URL "https://github.com/Mavergreen/swift-runtime/releases/latest/download/appcast.xml"
  ICON "${CMAKE_SOURCE_DIR}/updater/swift-runtime-updater.icns"
  VERSION "${MAVSWIFT_VERSION}"
  LOG_PREFIX "MavSwiftUpdater"
  CONFIRM_TITLE "Mavericks Swift Runtime updated"
  CONFIRM_BODY "The Swift runtime in /usr/local/mavergreen/swift-runtime was updated."
  RELAUNCH_MARKER "/tmp/.mavericks-swift-updater-relaunched"
  # no PANE_HINT_KEY -> background-found updates post an NSUserNotification (headless runtime, no pane)
)
