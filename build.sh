#!/bin/bash
# Build CmdBook.app without Xcode. Requires only the macOS Command Line Tools.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/CmdBook.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"

mkdir -p "$MACOS" "$RESOURCES"
# A non-Mach-O file inside Contents/MacOS breaks ad-hoc signing; keep resources out of it.
rm -f "$MACOS/examples.json"

SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$ROOT/Sources" -name '*.swift' -type f | sort)

if [ ! -f "$ROOT/Resources/CmdBook.icns" ]; then
    echo "Icon missing; generating it..."
    "$ROOT/make-icon.sh"
fi

echo "Compiling ${#SOURCES[@]} Swift sources..."
/usr/bin/swiftc \
    -swift-version 5 \
    -O \
    -target arm64-apple-macosx13.0 \
    "${SOURCES[@]}" \
    -o "$MACOS/CmdBook"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/examples.json" "$RESOURCES/examples.json"
cp "$ROOT/Resources/tool-zh.json" "$RESOURCES/tool-zh.json"
if [ -f "$ROOT/Resources/CmdBook.icns" ]; then
    cp "$ROOT/Resources/CmdBook.icns" "$RESOURCES/CmdBook.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

/usr/bin/codesign -s - --force "$APP" >/dev/null 2>&1 || echo "Warning: ad-hoc signing skipped."

echo "Built: $APP"
echo "Headless check: $MACOS/CmdBook --verify"
echo "Full scan:      $MACOS/CmdBook --scan"
echo "Launch app:     open $APP"
