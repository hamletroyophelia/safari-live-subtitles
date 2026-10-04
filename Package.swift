// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SafariLiveSubtitles",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "LiveLingo", targets: ["LiveLingo"])],
    targets: [.executableTarget(name: "LiveLingo", path: "Sources")],
    swiftLanguageModes: [.v5]
)
