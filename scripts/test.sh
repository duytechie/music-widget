#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/build/ModuleCache"
export SWIFT_MODULECACHE_PATH="$PROJECT_DIR/build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift test --disable-sandbox --scratch-path "$PROJECT_DIR/build/tests"
