// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EidisMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "EidisMac", path: "Sources/EidisMac")
    ]
)
