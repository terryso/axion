import Foundation

enum AppArchitectureUpgradeExecutionStatus: Equatable, Sendable {
    case succeeded
    case failed(exitCode: Int32)
    case launchFailed(String)
    case skipped(String)
}

struct AppArchitectureUpgradeExecutionResult: Equatable, Sendable {
    let status: AppArchitectureUpgradeExecutionStatus
    let commands: [String]
    let stdoutSummary: String
    let stderrSummary: String
}

struct ProcessLaunchResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessOutputStream: Equatable, Sendable {
    case stdout
    case stderr
}

struct ProcessOutputChunk: Equatable, Sendable {
    let stream: ProcessOutputStream
    let text: String
}

struct AppArchitectureUpgradeProgress: Equatable, Sendable {
    let command: String
    let stream: ProcessOutputStream
    let text: String
}

typealias ProcessOutputHandler = @Sendable (ProcessOutputChunk) -> Void
typealias AppArchitectureUpgradeProgressHandler = @Sendable (AppArchitectureUpgradeProgress) -> Void

protocol ProcessLaunching: Sendable {
    func run(
        executable: String,
        arguments: [String],
        onOutput: ProcessOutputHandler?
    ) async throws -> ProcessLaunchResult
}

extension ProcessLaunching {
    func run(executable: String, arguments: [String]) async throws -> ProcessLaunchResult {
        try await run(executable: executable, arguments: arguments, onOutput: nil)
    }
}

protocol AppArchitectureUpgradeExecuting: Sendable {
    func execute(
        plan: AppArchitectureUpgradePlan,
        onProgress: AppArchitectureUpgradeProgressHandler?
    ) async -> AppArchitectureUpgradeExecutionResult
}

extension AppArchitectureUpgradeExecuting {
    func execute(plan: AppArchitectureUpgradePlan) async -> AppArchitectureUpgradeExecutionResult {
        await execute(plan: plan, onProgress: nil)
    }
}

protocol AppArchitecturePostUpgradeScanning: Sendable {
    func rescan(item: AppArchitectureItem) async -> AppArchitectureItem?
}

struct DefaultAppArchitectureUpgradeExecutor: AppArchitectureUpgradeExecuting {
    let processLauncher: any ProcessLaunching

    init(processLauncher: any ProcessLaunching = FoundationProcessLauncher()) {
        self.processLauncher = processLauncher
    }

    func execute(
        plan: AppArchitectureUpgradePlan,
        onProgress: AppArchitectureUpgradeProgressHandler? = nil
    ) async -> AppArchitectureUpgradeExecutionResult {
        guard plan.status == .upgradeAvailable else {
            return skipped(plan: plan, reason: "当前计划不可执行。")
        }
        guard plan.source == .homebrew else {
            return skipped(plan: plan, reason: "当前只支持 Homebrew 升级执行。")
        }
        guard !plan.requiresSudo else {
            return skipped(plan: plan, reason: "当前计划需要 sudo，Axion 不自动执行。")
        }
        guard !plan.executableCommands.isEmpty else {
            return skipped(plan: plan, reason: "当前计划没有可执行命令。")
        }

        var stdoutParts: [String] = []
        var stderrParts: [String] = []
        for (index, command) in plan.executableCommands.enumerated() {
            guard let executable = command.first, !executable.isEmpty else {
                return skipped(plan: plan, reason: "升级命令为空。")
            }
            let displayCommand = plan.displayCommands.indices.contains(index)
                ? plan.displayCommands[index]
                : ([executable] + command.dropFirst()).joined(separator: " ")
            do {
                let result = try await processLauncher.run(
                    executable: executable,
                    arguments: Array(command.dropFirst()),
                    onOutput: { chunk in
                        onProgress?(AppArchitectureUpgradeProgress(
                            command: displayCommand,
                            stream: chunk.stream,
                            text: chunk.text
                        ))
                    }
                )
                stdoutParts.append(result.stdout)
                stderrParts.append(result.stderr)
                guard result.exitCode == 0 else {
                    return AppArchitectureUpgradeExecutionResult(
                        status: .failed(exitCode: result.exitCode),
                        commands: plan.displayCommands,
                        stdoutSummary: Self.summary(stdoutParts.joined(separator: "\n")),
                        stderrSummary: Self.summary(stderrParts.joined(separator: "\n"))
                    )
                }
            } catch {
                return AppArchitectureUpgradeExecutionResult(
                    status: .launchFailed(error.localizedDescription),
                    commands: plan.displayCommands,
                    stdoutSummary: Self.summary(stdoutParts.joined(separator: "\n")),
                    stderrSummary: Self.summary(stderrParts.joined(separator: "\n"))
                )
            }
        }

        return AppArchitectureUpgradeExecutionResult(
            status: .succeeded,
            commands: plan.displayCommands,
            stdoutSummary: Self.summary(stdoutParts.joined(separator: "\n")),
            stderrSummary: Self.summary(stderrParts.joined(separator: "\n"))
        )
    }

    private func skipped(plan: AppArchitectureUpgradePlan, reason: String) -> AppArchitectureUpgradeExecutionResult {
        AppArchitectureUpgradeExecutionResult(
            status: .skipped(reason),
            commands: plan.displayCommands,
            stdoutSummary: "",
            stderrSummary: ""
        )
    }

    static func summary(_ value: String, maxCharacters: Int = 600) -> String {
        let sanitized = AppArchitectureFormatter.sanitize(value)
        guard !sanitized.isEmpty else { return "-" }
        guard sanitized.count > maxCharacters else { return sanitized }
        return String(sanitized.prefix(maxCharacters - 1)) + "…"
    }
}

struct FoundationProcessLauncher: ProcessLaunching {
    func run(
        executable: String,
        arguments: [String],
        onOutput: ProcessOutputHandler? = nil
    ) async throws -> ProcessLaunchResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        let accumulator = ProcessOutputAccumulator()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            accumulator.capture(handle.availableData, stream: .stdout, onOutput: onOutput)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            accumulator.capture(handle.availableData, stream: .stderr, onOutput: onOutput)
        }

        try process.run()
        process.waitUntilExit()

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        accumulator.capture(stdout.fileHandleForReading.readDataToEndOfFile(), stream: .stdout, onOutput: onOutput)
        accumulator.capture(stderr.fileHandleForReading.readDataToEndOfFile(), stream: .stderr, onOutput: onOutput)

        let (finalStdoutData, finalStderrData) = accumulator.snapshot()
        let stdoutText = String(data: finalStdoutData, encoding: .utf8) ?? ""
        let stderrText = String(data: finalStderrData, encoding: .utf8) ?? ""
        return ProcessLaunchResult(
            exitCode: process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText
        )
    }
}

private final class ProcessOutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func capture(_ data: Data, stream: ProcessOutputStream, onOutput: ProcessOutputHandler?) {
        guard !data.isEmpty else { return }
        lock.lock()
        switch stream {
        case .stdout:
            stdoutData.append(data)
        case .stderr:
            stderrData.append(data)
        }
        lock.unlock()

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            onOutput?(ProcessOutputChunk(stream: stream, text: text))
        }
    }

    func snapshot() -> (stdout: Data, stderr: Data) {
        lock.lock()
        defer { lock.unlock() }
        return (stdoutData, stderrData)
    }
}

struct DefaultAppArchitecturePostUpgradeScanner: AppArchitecturePostUpgradeScanning {
    let scanner: any AppArchitectureScanning

    init(scanner: any AppArchitectureScanning = AppArchitectureScanService()) {
        self.scanner = scanner
    }

    func rescan(item: AppArchitectureItem) async -> AppArchitectureItem? {
        let options = AppArchitectureScanOptions(
            filter: item.name,
            includeSystemApps: item.isSystemApp,
            includeAllArchitectures: true,
            scope: item.source == .application ? .appsOnly : .packagesOnly,
            limit: 200
        )
        let result = await scanner.scan(options: options)
        return result.items.first { candidate in
            candidate.source == item.source && candidate.name == item.name
        } ?? result.items.first { candidate in
            candidate.source == item.source
        }
    }
}
