#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
app_path="$project_dir/build/双语直播字幕.app"
if [[ ! -x "$app_path/Contents/MacOS/LiveLingo" ]]; then
    "$project_dir/scripts/build.sh"
fi
open "$app_path"
