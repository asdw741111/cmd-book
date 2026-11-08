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

# A broken bundle is worse than a failed build: refuse to ship it.
for name in examples.json tool-zh.json CmdBook.icns; do
    if [ ! -s "$RESOURCES/$name" ]; then
        echo "ERROR: missing or empty bundle resource: $name" >&2
        exit 1
    fi
done
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null || {
    echo "ERROR: Info.plist is invalid" >&2
    exit 1
}
for name in examples.json tool-zh.json; do
    /usr/bin/python3 -m json.tool "$RESOURCES/$name" >/dev/null || {
        echo "ERROR: invalid JSON resource: $name" >&2
        exit 1
    }
done
if ! /usr/bin/codesign -s - --force "$APP" >/dev/null 2>&1; then
    echo "ERROR: ad-hoc signing failed; refusing to ship an unsigned bundle." >&2
    exit 1
fi

echo "Built: $APP"
echo "Headless check: $MACOS/CmdBook --verify"
echo "Full scan:      $MACOS/CmdBook --scan"
echo "Launch app:     open $APP"
