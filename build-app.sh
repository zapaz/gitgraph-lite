#!/bin/zsh
set -eu
ROOT="${0:A:h}"
BUILD="${ROOT}/../../work/build"
CACHE="${ROOT}/../../work/cache"
APP="${ROOT}/../GitGraph Lite.app"
cd "$ROOT"
mkdir -p "$CACHE/clang" "$CACHE/swift" "$CACHE/config" "$CACHE/security"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/clang"
OPTS=(--scratch-path "$BUILD" --cache-path "$CACHE/swift" --config-path "$CACHE/config" --security-path "$CACHE/security" --disable-sandbox --build-system native -debug-info-format none)
swift build -c release --product GitGraphLite "${OPTS[@]}"
BIN="$(swift build -c release "${OPTS[@]}" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/GitGraphLite" "$APP/Contents/MacOS/GitGraphLite"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GitGraphLite</string>
<key>CFBundleIdentifier</key><string>local.gitgraphlite.app</string>
<key>CFBundleName</key><string>GitGraph Lite</string>
<key>CFBundleDisplayName</key><string>GitGraph Lite</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>GitGraph Lite — independent implementation, 2026.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
