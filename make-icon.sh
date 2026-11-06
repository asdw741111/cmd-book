#!/bin/bash
# Regenerate Resources/CmdBook.icns from Scripts/MakeIcon.swift.
# Requires only the macOS Command Line Tools (swiftc, sips, iconutil).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/.build"
ICONSET="$BUILD/CmdBook.iconset"

mkdir -p "$BUILD"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

echo "Drawing 1024x1024 master icon..."
/usr/bin/swiftc -swift-version 5 "$ROOT/Scripts/MakeIcon.swift" -o "$BUILD/make-icon"
"$BUILD/make-icon" "$ICONSET/icon_512x512@2x.png"

MASTER="$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    if [ "$size" != "512" ]; then
        double=$((size * 2))
        /usr/bin/sips -z "$double" "$double" "$MASTER" \
            --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    fi
done

/usr/bin/iconutil -c icns "$ICONSET" -o "$ROOT/Resources/CmdBook.icns"
echo "Generated: $ROOT/Resources/CmdBook.icns"
