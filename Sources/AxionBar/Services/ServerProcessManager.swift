import Foundation
import os.log

@MainActor
final class ServerProcessManager: ObservableObject {
    private var serverProcess: Process?
    private(set) var isServerManagedByUs = false
    @Published var lastError: String?

    private let logger = Logger(subsystem: "com.axion.AxionBar", category: "ServerProcess")

    nonisolated static func findAxionCLI() -> String? {
        // 1. Try $PATH lookup via /usr/bin/which
        let whichTask = Process()
        whichTask.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichTask.arguments = ["axion"]
        let pipe = Pipe()
        whichTask.standardOutput = pipe
        do {
            try whichTask.run()
            whichTask.waitUntilExit()
            if whichTask.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}

        // 2. Try Homebrew path
        let homebrewPath = "/opt/homebrew/bin/axion"
        if FileManager.default.isExecutableFile(atPath: homebrewPath) {
            return homebrewPath
        }

        // 3. Try /usr/local/bin (Intel Macs)
        let localBinPath = "/usr/local/bin/axion"
        if FileManager.default.isExecutableFile(atPath: localBinPath) {
            return localBinPath
        }

        return nil
    }

    func startServer(healthChecker: BackendHealthChecker) {
        guard serverProcess == nil else { return }
        lastError = nil

        guard let cliPath = Self.findAxionCLI() else {
            lastError = "未找到 axion 命令行工具"
            logger.error("Failed to locate axion CLI binary")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["server", "--port", "4242"]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.serverProcess = nil
                self?.isServerManagedByUs = false
            }
        }

        do {
            try process.run()
            serverProcess = process
            isServerManagedByUs = true

            Task {
                for _ in 0..<10 {
                    let healthy = await healthChecker.checkOnce()
                    if healthy { return }
                    try? await Task.sleep(for: .seconds(1))
                }
                self.lastError = "服务启动超时（10秒）"
                self.logger.error("Server health check timed out after 10s")
            }
        } catch {
            serverProcess = nil
            isServerManagedByUs = false
            lastError = "启动服务失败: \(error.localizedDescription)"
            logger.error("Failed to start server: \(error)")
        }
    }

    func stopServer() {
        guard let process = serverProcess else { return }
        process.terminate()
        serverProcess = nil
        isServerManagedByUs = false
    }
}
