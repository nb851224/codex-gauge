#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_dir="$project_dir/dist/Codex Gauge.app"

cd "$project_dir"
export SWIFTPM_MODULECACHE_OVERRIDE="/tmp/codex-gauge-swiftpm"
export CLANG_MODULE_CACHE_PATH="/tmp/codex-gauge-clang"
swift build -c release --disable-sandbox

mkdir -p "$app_dir/Contents/MacOS"
cp ".build/release/CodexGauge" "$app_dir/Contents/MacOS/CodexGauge"
cp "Resources/Info.plist" "$app_dir/Contents/Info.plist"

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"
