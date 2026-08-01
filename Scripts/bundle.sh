#!/bin/bash
# Builds PulseMonitor and assembles a runnable .app bundle in build/.
#
# Swift Package Manager produces a bare executable; macOS needs the surrounding
# bundle structure plus an Info.plist before the app can register with the
# window server and appear in the Dock.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/PulseMonitor.app"
VERSION="${1:-2.0.0}"

echo "Building release binary…"
swift build -c release --disable-sandbox

echo "Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/PulseMonitor "$APP/Contents/MacOS/PulseMonitor"
cp PulseMonitor/Resources/Info.plist "$APP/Contents/Info.plist"

# Keep the bundle's version in step with the release being cut.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist" 2>/dev/null || true

# Ad-hoc signature so Gatekeeper will run it locally, and clear the quarantine
# flag that would otherwise block a freshly built bundle.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "warning: ad-hoc signing failed"
xattr -cr "$APP" 2>/dev/null || true

echo "Done: $APP"
