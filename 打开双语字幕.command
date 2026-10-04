#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
installed_app="/Applications/双语直播字幕.app"
if [[ -x "$installed_app/Contents/MacOS/LiveLingo" ]] && \
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist" 2>/dev/null)" == "local.livelingo.safari-live-subtitles" ]]; then
    open "$installed_app"
    exit 0
fi
app_path="$project_dir/build/双语直播字幕.app"
if [[ ! -x "$app_path/Contents/MacOS/LiveLingo" ]]; then
    "$project_dir/scripts/build.sh"
fi
open "$app_path"
