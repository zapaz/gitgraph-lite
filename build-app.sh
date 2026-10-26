#!/bin/zsh
set -eu
ROOT="${0:A:h}"
WORK="${GITGRAPH_BUILD_ROOT:-${ROOT}/.build-local}"
BUILD="${WORK}/build"
CACHE="${WORK}/cache"
APP="${GITGRAPH_APP_PATH:-${ROOT}/dist/GitGraph Lite.app}"
cd "$ROOT"
mkdir -p "$CACHE/clang" "$CACHE/swift" "$CACHE/config" "$CACHE/security"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/clang"
OPTS=(--scratch-path "$BUILD" --cache-path "$CACHE/swift" --config-path "$CACHE/config" --security-path "$CACHE/security" --disable-sandbox --build-system native -debug-info-format none)
swift build -c release --product GitGraphLite "${OPTS[@]}"
BIN="$(swift build -c release "${OPTS[@]}" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/GitGraphLite" "$APP/Contents/MacOS/GitGraphLite"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GitGraphLite</string>
<key>CFBundleIdentifier</key><string>local.gitgraphlite.app</string>
<key>CFBundleName</key><string>GitGraph Lite</string>
<key>CFBundleDisplayName</key><string>GitGraph Lite</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleShortVersionString</key><string>0.5.1</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSDocumentsFolderUsageDescription</key><string>Open and manage Git repositories you choose in Documents.</string>
<key>NSDesktopFolderUsageDescription</key><string>Open and manage Git repositories you choose on the Desktop.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Open and manage Git repositories you choose in Downloads.</string>
<key>NSHumanReadableCopyright</key><string>GitGraph Lite — independent implementation, 2026.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "$APP"
