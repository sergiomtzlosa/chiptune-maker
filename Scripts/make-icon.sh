#!/bin/bash
# Regenerates ChiptuneMaker/Resources/AppIcon.icns from Scripts/make-icon.swift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SOURCE="$TMP/AppIcon-1024.png"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

xcrun swift "$ROOT/Scripts/make-icon.swift" "$SOURCE"

for spec in \
    "16 icon_16x16.png" \
    "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" \
    "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" \
    "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" \
    "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" \
    "1024 icon_512x512@2x.png"; do
    set -- $spec
    sips -z "$1" "$1" "$SOURCE" --out "$ICONSET/$2" >/dev/null
done

mkdir -p "$ROOT/ChiptuneMaker/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/ChiptuneMaker/Resources/AppIcon.icns"
echo "Wrote ChiptuneMaker/Resources/AppIcon.icns"
