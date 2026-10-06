#!/bin/zsh
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
mkdir -p build/module-cache
xcrun swiftc -parse-as-library -module-cache-path "$project_dir/build/module-cache" \
    Sources/Captions.swift Sources/GameGlossary.swift Tests/CaptionTests.swift -o build/caption-tests
build/caption-tests
xcrun swiftc -parse-as-library -module-cache-path "$project_dir/build/module-cache" \
    Sources/Captions.swift Sources/GameGlossary.swift Tests/GlossaryTests.swift -o build/glossary-tests
build/glossary-tests
xcrun swiftc -parse-as-library -module-cache-path "$project_dir/build/module-cache" \
    Sources/PCMConverter.swift Tests/AudioTests.swift -o build/audio-tests
build/audio-tests
xcrun swiftc -parse-as-library -module-cache-path "$project_dir/build/module-cache" \
    Sources/Captions.swift Sources/GameGlossary.swift Sources/LiveScheduling.swift Tests/SchedulingTests.swift -o build/scheduling-tests
build/scheduling-tests
