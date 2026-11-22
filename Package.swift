// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DisplayToggle",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "DisplayToggleCore"),
        .executableTarget(name: "DisplayToggle", dependencies: ["DisplayToggleCore"]),
        .testTarget(name: "DisplayToggleCoreTests", dependencies: ["DisplayToggleCore"]),
    ]
)
