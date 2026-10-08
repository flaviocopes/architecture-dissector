#!/bin/sh
# Renders docs/screenshot-{light,dark}.png and docs/screenshot-compare-{light,dark}.png from the
# real app views, with the architectures in scripts/demo loaded into a demo data folder.
# The capture app has its own bundle ID and data folder, so your settings and apps stay untouched.
# With an architecture JSON, it renders only that one, to check how a real map lays out.
# Usage: scripts/screenshot.sh [output folder] [architecture.json]
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/docs"}
EXTRA=${2:+$(cd "$(dirname "$2")" && pwd)/$(basename "$2")}
APP="$ROOT/build/screenshot/Architecture Dissector Screenshot.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$OUT"
find "$ROOT/Blueprint" -name '*.swift' ! -name BlueprintApp.swift -print0 |
  xargs -0 swiftc -O -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 \
    "$ROOT/scripts/screenshot.swift" -o "$APP/Contents/MacOS/Screenshot"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Screenshot</string>
  <key>CFBundleIdentifier</key>
  <string>com.flaviocopes.blueprint.screenshot</string>
  <key>CFBundleName</key>
  <string>Architecture Dissector</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
open -n "$APP" --args "$OUT" "$ROOT/build/demo-home" "$ROOT/scripts/demo" ${EXTRA:+"$EXTRA"} -AppleLocale en_US -AppleLanguages '(en)'
sleep 1
while pgrep -f "Architecture Dissector Screenshot.app/Contents/MacOS" >/dev/null; do sleep 1; done
ls -la "$OUT"/screenshot*.png
