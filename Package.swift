// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyGlow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "KeyGlow",
            path: "Sources/KeyGlow",
            resources: [
                .copy("Resources/icon-16@2x.png"),
                .copy("Resources/menubar-icon.svg"),
            ]
        )
    ]
)
