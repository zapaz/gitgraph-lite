#!/bin/zsh
# Requires an available macOS desktop session. Run build-app.sh first.
set -eu
ROOT="${0:A:h:h}"
WORK="${GITGRAPH_BUILD_ROOT:-${ROOT}/.build-local}"
BUILD="${WORK}/build/$(uname -m)-apple-macosx/release"
CHECK="${WORK}/grouping-ui-check"
mkdir -p "$CHECK" "$WORK/cache/clang"
export CLANG_MODULE_CACHE_PATH="$WORK/cache/clang"
# Compile the real app sources, replacing only its event-loop entry point.
sed '/^let app = NSApplication.shared/,$d' "$ROOT/Sources/GitGraphLite/main.swift" > "$CHECK/main.swift"
cat "$ROOT/Tests/GroupingUI.swift" "$ROOT/Tests/MenuUsageUI.swift" >> "$CHECK/main.swift"
SOURCES=("$ROOT"/Sources/GitGraphLite/*.swift)
SOURCES=("${(@)SOURCES:#*/main.swift}")
swiftc -module-cache-path "$WORK/cache/clang" -I "$BUILD/Modules" "${SOURCES[@]}" "$CHECK/main.swift" "$BUILD"/GitGraphCore.build/*.o -o "$CHECK/GroupingUIChecks"
"$CHECK/GroupingUIChecks"
