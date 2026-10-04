// swift-tools-version: 6.0
import PackageDescription
import Foundation

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let excludedPaths = ["Tests", "scripts", "docs", "examples", "Resources/Info.plist", "Resources/ICON_PROMPT.md", "Resources/AppIcon.png", "README.md", "打开双语字幕.command",
    "AGENTS.md", "MEMORY.md", "PRIVACY.md", "THIRD_PARTY_NOTICES.md", "build", "verification", "exports", "dist"]
    .filter { FileManager.default.fileExists(atPath: projectRoot.appendingPathComponent($0).path) }

let package = Package(
    name: "SafariLiveSubtitles",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "LiveLingo", targets: ["LiveLingo"])],
    targets: [.executableTarget(name: "LiveLingo", path: ".",
        exclude: excludedPaths,
        sources: ["Sources"], resources: [.copy("Resources/game-glossary.json")])],
    swiftLanguageModes: [.v5]
)
