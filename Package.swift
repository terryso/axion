// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "axion",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "AxionCLI", targets: ["AxionCLI"]),
        .executable(name: "AxionHelper", targets: ["AxionHelper"]),
        .library(name: "AxionCore", targets: ["AxionCore"]),
    ],
    dependencies: [
        .package(path: "../open-agent-sdk-swift"),
        .package(
            url: "https://github.com/terryso/swift-mcp.git",
            from: "0.1.5"
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
                .product(name: "MCP", package: "swift-mcp"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/AxionCLI"
        ),
        .executableTarget(
            name: "AxionHelper",
            dependencies: [
                "AxionCore",
                .product(name: "MCP", package: "swift-mcp"),
                .product(name: "MCPTool", package: "swift-mcp"),
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
            dependencies: [
                "AxionCLI",
                "AxionCore",
                .product(name: "MCP", package: "swift-mcp"),
                .product(name: "OpenAgentSDK", package: "open-agent-sdk-swift"),
            ],
            path: "Tests/AxionCLITests",
            exclude: ["Integration"]
        ),
        .testTarget(
            name: "AxionHelperTests",
            dependencies: [
                "AxionHelper",
                .product(name: "MCP", package: "swift-mcp"),
                .product(name: "MCPTool", package: "swift-mcp"),
                "AxionCore",
            ],
            path: "Tests/AxionHelperTests",
            exclude: ["Integration"]
        ),
        .testTarget(
            name: "AxionCLIIntegrationTests",
            dependencies: [
                "AxionCLI",
                "AxionCore",
                .product(name: "MCP", package: "swift-mcp"),
                .product(name: "OpenAgentSDK", package: "open-agent-sdk-swift"),
            ],
            path: "Tests/AxionCLITests/Integration"
        ),
        .testTarget(
            name: "AxionHelperIntegrationTests",
            dependencies: [
                "AxionHelper",
                .product(name: "MCP", package: "swift-mcp"),
                .product(name: "MCPTool", package: "swift-mcp"),
                "AxionCore",
            ],
            path: "Tests/AxionHelperTests/Integration"
        ),
    ]
)
