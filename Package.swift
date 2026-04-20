// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeTokenManager",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeTokenManager", targets: ["ClaudeTokenManager"])
    ],
    targets: [
        .target(
            name: "ClaudeTokenManagerCore",
            path: "Sources/ClaudeTokenManagerCore"
        ),
        .executableTarget(
            name: "ClaudeTokenManager",
            dependencies: ["ClaudeTokenManagerCore"],
            path: "Sources/ClaudeTokenManager",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
