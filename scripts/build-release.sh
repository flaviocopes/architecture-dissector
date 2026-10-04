#!/bin/sh
# Builds a universal (Apple silicon and Intel) Blueprint.app, with the blueprint command inside, and
# writes dist/Blueprint-<version>.zip. Signs it with Flavio Copes's Developer ID and notarizes it when that
# certificate is in the keychain, and keeps Xcode's ad-hoc signature everywhere else (CI, forks).
# The name and version come from project.yml.
# Usage: scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
NAME=$(sed -n 's/^name: *//p' project.yml)
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
BUILD="$ROOT/build/release"
APP="$BUILD/Release/$NAME.app"
ZIP="$ROOT/dist/$NAME-$VERSION.zip"
CHECK=$(mktemp -d)
trap 'rm -rf "$CHECK"' EXIT

rm -rf "$BUILD" "$ZIP"
mkdir -p dist
xcodebuild -project "$NAME.xcodeproj" -target "$NAME" -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO SYMROOT="$BUILD" -quiet build

lipo "$APP/Contents/MacOS/$NAME" -verify_arch arm64 x86_64
lipo "$APP/Contents/Helpers/blueprint" -verify_arch arm64 x86_64

identity=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: Flavio Copes \(DGFKNTAG99\)"/ { print $2; exit }')
if [ -n "$identity" ]; then
  signature="Developer ID"
  # Every Mach-O inside-out (no --deep), the bundled command included, then the app. Signing without
  # --entitlements drops the get-task-allow entitlement Xcode adds, which notarization rejects.
  find "$APP" -depth -type f | while IFS= read -r file; do
    case $(file -b "$file") in
      *Mach-O*) codesign --force --options runtime --timestamp --sign "$identity" "$file" ;;
    esac
  done
  codesign --force --options runtime --timestamp --sign "$identity" "$APP"
else
  signature="ad-hoc"
fi
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ "$signature" = "Developer ID" ]; then
  result=$(xcrun notarytool submit "$ZIP" --keychain-profile notary --wait --output-format json)
  if [ "$(printf '%s' "$result" | plutil -extract status raw -o - -)" != "Accepted" ]; then
    printf '%s\n' "$result" >&2
    xcrun notarytool log "$(printf '%s' "$result" | plutil -extract id raw -o - -)" --keychain-profile notary >&2
    exit 1
  fi
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose "$APP"
fi

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/$NAME.app"

echo "Built $ZIP, $signature signed"
shasum -a 256 "$ZIP"
