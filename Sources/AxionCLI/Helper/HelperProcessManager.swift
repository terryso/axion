import Foundation
import MCP
import OpenAgentSDK

import AxionCore

// MARK: - HelperTransportProtocol

/// Protocol abstracting MCPStdioTransport for testability.
///
/// Production uses ``RealHelperTransport`` wrapping ``MCPStdioTransport``.
/// Tests inject ``MockHelperTransport`` to isolate from real Process management.
protocol HelperTransportProtocol: Sendable {
    func connect() async throws
    func disconnect() async
    func getIsRunning() async -> Bool
    /// Returns the underlying Transport for MCPClient.connect's transport factory.
    func getTransport() async -> (any Transport)?
}

// MARK: - RealHelperTransport

/// Production transport wrapping SDK's ``MCPStdioTransport``.
actor RealHelperTransport: HelperTransportProtocol {
    private let transport: MCPStdioTransport

    init(config: McpStdioConfig) {
        self.transport = MCPStdioTransport(config: config)
    }

    func connect() async throws {
        try await transport.connect()
    }

    func disconnect() async {
        await transport.disconnect()
    }

    func getIsRunning() async -> Bool {
        await transport.isRunning
    }

    func getTransport() async -> (any Transport)? {
        transport as any Transport
    }
}

// MARK: - HelperMCPClientProtocol

/// Protocol abstracting MCPClient for testability.
///
/// Production uses ``RealHelperMCPClient`` wrapping ``MCPClient``.
/// Tests inject ``MockHelperMCPClient`` to control tool call results.
protocol HelperMCPClientProtocol: Sendable {
    func connect(transport: @escaping @Sendable () async throws -> any Transport) async throws
    func disconnect() async
    func callTool(name: String, arguments: [String: MCP.Value]?) async throws -> CallTool.Result
    func listTools() async throws -> ListTools.Result
}

// MARK: - RealHelperMCPClient

/// Production MCP client wrapping SDK's ``MCPClient``.
actor RealHelperMCPClient: HelperMCPClientProtocol {
    private let client: MCPClient

    init() {
        self.client = MCPClient(
            name: "AxionCLI",
            version: "1.0.0",
            reconnectionOptions: MCPClient.ReconnectionOptions(
                maxRetries: 0,
                initialDelay: .seconds(1),
                maxDelay: .seconds(1),
                delayGrowFactor: 1.0,
                healthCheckInterval: nil
            )
        )
    }

    func connect(transport: @escaping @Sendable () async throws -> any Transport) async throws {
        try await client.connect(transport: transport)
    }

    func disconnect() async {
        await client.disconnect()
    }

    func callTool(name: String, arguments: [String: MCP.Value]?) async throws -> CallTool.Result {
        try await client.callTool(name: name, arguments: arguments)
    }

    func listTools() async throws -> ListTools.Result {
        try await client.listTools()
    }
}

// MARK: - HelperProcessManager

/// Manages the AxionHelper process lifecycle and MCP connection.
///
/// Responsibilities:
/// - Start Helper process via MCPStdioTransport (AC1)
/// - Establish MCP client connection and confirm readiness (AC2)
/// - Graceful shutdown: disconnect MCP -> disconnect transport (AC3, AC4)
/// - Ctrl-C signal propagation (AC5)
/// - Crash detection and single restart (AC6)
///
/// Uses SDK components directly (FR37):
/// - ``MCPStdioTransport`` for process management and stdio JSON-RPC
/// - ``MCPClient`` for MCP handshake, tool discovery, and tool calls
actor HelperProcessManager {

    // MARK: - Private State

    /// MCP client for tool calls.
    private var mcpClient: HelperMCPClientProtocol?

    /// Transport for process management.
    private var transport: HelperTransportProtocol?

    /// Whether Helper has been restarted once after a crash.
    private var hasRestarted = false

    /// Background task monitoring for crash detection.
    private var monitorTask: _Concurrency.Task<Void, Never>?

    /// Whether stop() was called intentionally (not a crash).
    private var isStopping = false

    /// Whether the manager is currently connected.
    private var connected = false

    // MARK: - Initialization

    init() {}

    /// Creates a HelperProcessManager with injected transport and client for testing.
    ///
    /// Sets `connected = true` so that `callTool()` and `listTools()` can be called
    /// immediately without going through `start()` (which requires a real Helper path).
    init(
        transport: HelperTransportProtocol,
        client: HelperMCPClientProtocol
    ) {
        self.transport = transport
        self.mcpClient = client
        self.connected = true
    }

    // MARK: - Public API

    /// Starts the Helper process and establishes MCP connection.
    ///
    /// Flow:
    /// 1. Resolve Helper path via ``HelperPathResolver``
    /// 2. Create ``MCPStdioTransport`` and launch process
    /// 3. Create ``MCPClient`` and perform MCP handshake
    /// 4. Start crash monitoring
    ///
    /// - Throws: ``AxionError/helperNotRunning`` if Helper path not found.
    /// - Throws: ``AxionError/helperConnectionFailed`` if MCP handshake fails.
    func start() async throws {
        guard let helperPath = HelperPathResolver.resolveHelperPath() else {
            throw AxionError.helperNotRunning
        }

        let config = McpStdioConfig(command: helperPath)

        // Create a single transport wrapper for both process management and MCP communication.
        let transport = RealHelperTransport(config: config)
        self.transport = transport

        do {
            // Launch the Helper process via transport
            try await transport.connect()

            // Get the underlying MCPStdioTransport for MCPClient handshake.
            // Uses the same transport to avoid launching a second Helper process.
            guard let rawTransport = await transport.getTransport() else {
                throw AxionError.helperConnectionFailed(reason: "Failed to access transport")
            }

            // Create MCP client and perform handshake
            let client = RealHelperMCPClient()
            try await client.connect { rawTransport }
            self.mcpClient = client

            connected = true
            isStopping = false

            // Start crash monitoring
            startCrashMonitoring()
        } catch let error as AxionError {
            await cleanup()
            throw error
        } catch {
            await cleanup()
            throw AxionError.helperConnectionFailed(reason: error.localizedDescription)
        }
    }

    /// Stops the Helper process gracefully.
    ///
    /// Flow (AC3, AC4):
    /// 1. Disconnect MCP client
    /// 2. Disconnect transport (terminates process)
    func stop() async {
        isStopping = true
        connected = false
        monitorTask?.cancel()
        monitorTask = nil
        await cleanup()
    }

    /// Returns whether the Helper process is running and connected.
    func isRunning() async -> Bool {
        guard connected, let transport else { return false }
        return await transport.getIsRunning()
    }

    /// Calls a tool on the Helper via MCP.
    ///
    /// Converts ``AxionCore.Value`` arguments to ``MCP.Value`` and extracts
    /// text from the result's content blocks.
    ///
    /// - Parameters:
    ///   - name: The MCP tool name (snake_case).
    ///   - arguments: Tool arguments using ``AxionCore.Value`` types.
    /// - Returns: Extracted text from the tool result.
    /// - Throws: ``AxionError/helperNotRunning`` if not connected.
    /// - Throws: ``AxionError/mcpError`` if the tool returns an error.
    func callTool(name: String, arguments: [String: AxionCore.Value]) async throws -> String {
        guard connected, let client = mcpClient else {
            throw AxionError.helperNotRunning
        }

        let mcpArgs = arguments.mapValues { toMCPValue($0) }

        let result: CallTool.Result
        do {
            result = try await client.callTool(name: name, arguments: mcpArgs)
        } catch {
            throw AxionError.mcpError(tool: name, reason: error.localizedDescription)
        }

        // Check for MCP-level errors
        if result.isError == true {
            let errorText = extractText(from: result.content)
            throw AxionError.mcpError(tool: name, reason: errorText.isEmpty ? "Unknown tool error" : errorText)
        }

        return extractText(from: result.content)
    }

    /// Lists available tools from the Helper.
    ///
    /// - Returns: Array of tool names.
    /// - Throws: ``AxionError/helperNotRunning`` if not connected.
    func listTools() async throws -> [String] {
        guard connected, let client = mcpClient else {
            throw AxionError.helperNotRunning
        }

        let result: ListTools.Result
        do {
            result = try await client.listTools()
        } catch {
            throw AxionError.helperConnectionFailed(reason: "Failed to list tools: \(error.localizedDescription)")
        }

        return result.tools.map(\.name)
    }

    /// Sets up SIGINT (Ctrl-C) signal handling to clean up Helper process (AC5).
    ///
    /// Signal handling is implemented via ``withTaskCancellationHandler``
    /// in the RunCommand layer. This method exists as a hook for
    /// future extension and to satisfy AC5 interface requirements.
    func setupSignalHandling() {
        // No-op: actual signal handling is done via withTaskCancellationHandler
        // in RunCommand. This method is retained for interface compatibility.
    }

    // MARK: - Private Helpers

    /// Converts ``AxionCore.Value`` to ``MCP.Value``.
    private func toMCPValue(_ value: AxionCore.Value) -> MCP.Value {
        switch value {
        case .string(let s): return .string(s)
        case .int(let i): return .int(i)
        case .bool(let b): return .bool(b)
        case .placeholder(let p): return .string(p)
        }
    }

    /// Extracts text content from MCP content blocks.
    private func extractText(from content: [ContentBlock]) -> String {
        let textParts = content.compactMap { block -> String? in
            if case .text(let text, _, _) = block { return text }
            return nil
        }
        return textParts.joined(separator: "\n")
    }

    /// Cleans up all resources.
    private func cleanup() async {
        if let client = mcpClient {
            await client.disconnect()
        }
        mcpClient = nil

        if let transport {
            await transport.disconnect()
        }
        self.transport = nil
        connected = false
    }

    /// Starts background crash monitoring.
    ///
    /// Periodically checks transport connection state. When the transport
    /// reports not running and it wasn't caused by an intentional ``stop()``,
    /// attempts a single restart (AC6).
    private func startCrashMonitoring() {
        monitorTask = _Concurrency.Task { [weak self] in
            // Wait a moment for initial connection to stabilize
            try? await _Concurrency.Task.sleep(for: .milliseconds(500))

            while !_Concurrency.Task.isCancelled {
                try? await _Concurrency.Task.sleep(for: .milliseconds(500))

                guard let self else { return }

                let running = await self.isRunning()
                let stopping = await self.isStopping
                let restarted = await self.hasRestarted

                if !running && !stopping && !restarted {
                    // Crash detected - attempt restart once
                    await self.performCrashRestart()
                    return
                }
            }
        }
    }

    /// Performs a single crash restart.
    private func performCrashRestart() async {
        guard !hasRestarted else { return }
        hasRestarted = true

        // Clean up old resources
        await cleanup()

        // Attempt restart
        do {
            try await start()
        } catch {
            // Restart failed - give up
            connected = false
        }
    }
}
