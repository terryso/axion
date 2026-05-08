// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "axion",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "AxionCLI", targets: ["AxionCLI"]),
        .executable(name: "AxionHelper", targets: ["AxionHelper"]),
        .library(name: "AxionCore", targets: ["AxionCore"]),
    ],
    dependencies: [
        .package(path: "../open-agent-sdk-swift"),
        .package(
            url: "https://github.com/DePasqualeOrg/mcp-swift-sdk.git",
            from: "0.1.0"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.5.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "AxionCLI",
            dependencies: [
                "AxionCore",
                .product(name: "OpenAgentSDK", package: "open-agent-sdk-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AxionCLI"
        ),
        .executableTarget(
            name: "AxionHelper",
            dependencies: [
                "AxionCore",
                .product(name: "MCP", package: "mcp-swift-sdk"),
                .product(name: "MCPTool", package: "mcp-swift-sdk"),
            ],
            path: "Sources/AxionHelper"
        ),
        .target(
            name: "AxionCore",
            path: "Sources/AxionCore"
        ),
        .testTarget(
            name: "AxionCoreTests",
            dependencies: ["AxionCore"],
            path: "Tests/AxionCoreTests"
        ),
        .testTarget(
            name: "AxionCLITests",
            dependencies: ["AxionCLI"],
            path: "Tests/AxionCLITests"
        ),
        .testTarget(
            name: "AxionHelperTests",
            dependencies: [
                "AxionHelper",
                .product(name: "MCP", package: "mcp-swift-sdk"),
                .product(name: "MCPTool", package: "mcp-swift-sdk"),
                "AxionCore",
            ],
            path: "Tests/AxionHelperTests"
        ),
    ]
)
