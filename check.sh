#!/bin/zsh
set -eu
ROOT="${0:A:h}"
WORK="${GITGRAPH_BUILD_ROOT:-${ROOT}/.build-local}"
CACHE="${WORK}/cache"
mkdir -p "$CACHE/clang" "$CACHE/swift" "$CACHE/config" "$CACHE/security"
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/clang"
cd "$ROOT"
swift run --scratch-path "$WORK/checks" --cache-path "$CACHE/swift" --config-path "$CACHE/config" --security-path "$CACHE/security" --disable-sandbox --build-system native -debug-info-format none GitGraphChecks
