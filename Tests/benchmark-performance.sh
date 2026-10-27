#!/bin/zsh
# Build the release app first. Uses the real Controller and AppKit tables.
set -eu
ROOT="${0:A:h:h}"
WORK="${GITGRAPH_BUILD_ROOT:-${ROOT}/.build-local}"
BUILD="$WORK/build/$(uname -m)-apple-macosx/release"
BENCH="$WORK/performance-benchmark"
if (( $# < 1 )); then
    echo "Usage: zsh Tests/benchmark-performance.sh REPOSITORY [OUTPUT_JSON] [ITERATIONS]" >&2
    exit 2
fi
mkdir -p "$BENCH" "$WORK/cache/clang"
sed '/^let app = NSApplication.shared/,$d' "$ROOT/Sources/GitGraphLite/main.swift" > "$BENCH/main.swift"
cat "$ROOT/Tests/Performance.swift" >> "$BENCH/main.swift"
SOURCES=("$ROOT"/Sources/GitGraphLite/*.swift)
SOURCES=("${(@)SOURCES:#*/main.swift}")
swiftc -O -module-cache-path "$WORK/cache/clang" -I "$BUILD/Modules" "${SOURCES[@]}" "$BENCH/main.swift" "$BUILD"/GitGraphCore.build/*.o -o "$BENCH/Performance"
"$BENCH/Performance" --repo "$1" --output "${2:-$BENCH/performance.json}" --iterations "${3:-5}"
