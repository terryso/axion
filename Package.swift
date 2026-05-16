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
        .executable(name: "AxionBar", targets: ["AxionBar"]),
        .library(name: "AxionCore", targets: ["AxionCore"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/terryso/open-agent-sdk-swift",
            from: "0.3.2"
        ),
        .package(
            url: "https://github.com/terryso/swift-mcp.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/ajevans99/swift-json-schema",
            from: "0.11.0"
        ),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.5.0"
        ),
        .package(
            url: "https://github.com/hummingbird-project/hummingbird.git",
            from: "2.22.0"
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
                .product(name: "Hummingbird", package: "hummingbird"),
            ],
            path: "Sources/AxionCLI"
        ),
        .executableTarget(
            name: "AxionHelper",
            dependencies: [
                "AxionCore",
                .product(name: "MCP", package: "swift-mcp"),
                .product(name: "MCPTool", package: "swift-mcp"),
                .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
            ],
            path: "Sources/AxionHelper"
        ),
        .executableTarget(
            name: "AxionBar",
            dependencies: [
                "AxionCore",
            ],
            path: "Sources/AxionBar"
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
            name: "AxionBarTests",
            dependencies: ["AxionBar", "AxionCore"],
            path: "Tests/AxionBarTests"
        ),
        .testTarget(
            name: "AxionCLITests",
            dependencies: [
                "AxionCLI",
                "AxionCore",
                .product(name: "MCP", package: "swift-mcp"),
                .product(name: "OpenAgentSDK", package: "open-agent-sdk-swift"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdTesting", package: "hummingbird"),
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
        .testTarget(
            name: "AxionE2ETests",
            dependencies: [
                "AxionCLI",
                "AxionCore",
                .product(name: "OpenAgentSDK", package: "open-agent-sdk-swift"),
                .product(name: "MCP", package: "swift-mcp"),
            ],
            path: "Tests/AxionE2ETests"
        ),
    ]
)
