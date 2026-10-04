#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/module-cache
app_dir="$project_dir/build/双语直播字幕.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
./scripts/make-icon.sh
xcrun swiftc -parse-as-library -swift-version 5 -O \
    -file-compilation-dir . -file-prefix-map "$project_dir=." \
    -target arm64-apple-macos26.0 \
    -module-cache-path "$project_dir/build/module-cache" \
    Sources/*.swift -o "$app_dir/Contents/MacOS/LiveLingo"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp build/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.livelingo.safari-live-subtitles \
    --requirements '=designated => identifier "local.livelingo.safari-live-subtitles"' "$app_dir"
codesign --verify --strict "$app_dir"
print "已构建：$app_dir"
