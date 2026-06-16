import Foundation
import Testing

@testable import AxionCLI

@Suite("App Architecture Upgrade Planning")
struct AppArchitectureUpgradePlanningTests {
    @Test("Homebrew formula path produces executable brew upgrade plan")
    func homebrewFormulaPathProducesPlan() async {
        let planner = DefaultAppArchitectureUpgradePlanner()
        let item = appItem(
            name: "legacy",
            displayPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            source: .homebrew
        )

        let plan = await planner.plan(for: item)

        #expect(plan.status == .upgradeAvailable)
        #expect(plan.packageIdentity == "legacy")
        #expect(plan.displayCommands == ["brew upgrade legacy"])
        #expect(plan.executableCommands == [["brew", "upgrade", "legacy"]])
        #expect(plan.requiresSudo == false)
        #expect(plan.confidence == .high)
        #expect(plan.postCheckPath == item.executablePath)
    }

    @Test("Homebrew formula can be inferred from display path when executable path is absent")
    func homebrewFormulaUsesDisplayPathFallback() async {
        let planner = DefaultAppArchitectureUpgradePlanner(homebrewCellarRoots: ["/custom/Cellar"])
        let item = AppArchitectureItem(
            name: "tool",
            displayPath: "/custom/Cellar/tool@2+safe/2.0/bin/tool",
            executablePath: nil,
            architectures: [.x86_64],
            isSystemApp: false,
            source: .homebrew
        )

        let plan = await planner.plan(for: item)

        #expect(plan.status == .upgradeAvailable)
        #expect(plan.packageIdentity == "tool@2+safe")
        #expect(plan.displayCommands == ["brew upgrade tool@2+safe"])
        #expect(plan.postCheckPath == item.displayPath)
    }

    @Test("Intel Homebrew prefix returns executable native migration plan")
    func intelHomebrewPrefixReturnsExecutableNativeMigrationPlan() async {
        let planner = DefaultAppArchitectureUpgradePlanner()
        let item = appItem(
            name: "aliyun-cli",
            displayPath: "/usr/local/Cellar/aliyun-cli/3.0.90/bin/aliyun",
            source: .homebrew
        )

        let plan = await planner.plan(for: item)

        #expect(plan.status == .upgradeAvailable)
        #expect(plan.packageIdentity == "aliyun-cli")
        #expect(plan.displayCommands == [
            "/opt/homebrew/bin/brew install aliyun-cli",
            "/usr/local/bin/brew uninstall aliyun-cli",
        ])
        #expect(plan.executableCommands == [
            ["/opt/homebrew/bin/brew", "install", "aliyun-cli"],
            ["/usr/local/bin/brew", "uninstall", "aliyun-cli"],
        ])
        #expect(plan.requiresSudo == false)
        #expect(plan.confidence == .high)
        #expect(plan.notes.contains { $0.contains("/usr/local/Cellar") })
        #expect(plan.notes.contains { $0.contains("安装成功后才卸载") })
    }

    @Test("Unsafe Homebrew formula path is unsupported")
    func unsafeHomebrewFormulaPathUnsupported() async {
        let planner = DefaultAppArchitectureUpgradePlanner()
        let plan = await planner.plan(for: appItem(
            name: "bad",
            displayPath: "/opt/homebrew/Cellar/bad;rm/1.0/bin/bad",
            source: .homebrew
        ))

        #expect(plan.status == .unsupported)
        #expect(plan.packageIdentity == nil)
        #expect(plan.displayCommands.isEmpty)
        #expect(plan.executableCommands.isEmpty)
    }

    @Test("Homebrew path outside Cellar is unsupported")
    func homebrewPathOutsideCellarUnsupported() async {
        let planner = DefaultAppArchitectureUpgradePlanner()
        let plan = await planner.plan(for: appItem(
            name: "loose",
            displayPath: "/opt/homebrew/bin/loose",
            source: .homebrew
        ))

        #expect(plan.status == .unsupported)
        #expect(plan.packageIdentity == nil)
        #expect(plan.displayCommands.isEmpty)
        #expect(plan.notes.contains { $0.contains("Cellar") })
    }

    @Test("MacPorts returns manual-only guidance and no executable command")
    func macPortsManualOnly() async {
        let planner = DefaultAppArchitectureUpgradePlanner()
        let plan = await planner.plan(for: appItem(
            name: "legacy-port",
            displayPath: "/opt/local/bin/legacy-port",
            source: .macPorts
        ))

        #expect(plan.status == .manualOnly)
        #expect(plan.requiresSudo)
        #expect(plan.displayCommands.isEmpty)
        #expect(plan.executableCommands.isEmpty)
        #expect(plan.notes.contains { $0.contains("MacPorts") })
    }

    @Test("Direct app returns manual-only vendor guidance")
    func directAppManualOnly() async {
        let planner = DefaultAppArchitectureUpgradePlanner()
        let plan = await planner.plan(for: appItem(
            name: "LegacyApp",
            displayPath: "/Applications/LegacyApp.app",
            executablePath: "/Applications/LegacyApp.app/Contents/MacOS/LegacyApp",
            source: .application
        ))

        #expect(plan.status == .manualOnly)
        #expect(plan.displayCommands.isEmpty)
        #expect(plan.executableCommands.isEmpty)
        #expect(plan.notes.contains { $0.contains("厂商") })
    }

    @Test("System app returns macOS update guidance")
    func systemAppManualOnly() async {
        let planner = DefaultAppArchitectureUpgradePlanner()
        let plan = await planner.plan(for: appItem(
            name: "SystemLegacy",
            displayPath: "/System/Applications/SystemLegacy.app",
            executablePath: "/System/Applications/SystemLegacy.app/Contents/MacOS/SystemLegacy",
            isSystemApp: true,
            source: .application
        ))

        #expect(plan.status == .manualOnly)
        #expect(plan.displayCommands.isEmpty)
        #expect(plan.notes.contains { $0.contains("macOS") })
    }

    @Test("Unknown architecture is unsupported")
    func unknownArchitectureUnsupported() async {
        let planner = DefaultAppArchitectureUpgradePlanner()
        let item = AppArchitectureItem(
            name: "Mystery",
            displayPath: "/Applications/Mystery.app",
            executablePath: nil,
            architectures: [],
            isSystemApp: false,
            source: .application
        )

        let plan = await planner.plan(for: item)

        #expect(plan.status == .unsupported)
        #expect(plan.displayCommands.isEmpty)
        #expect(plan.notes.contains { $0.contains("未能识别") })
    }

    @Test("Homebrew upgrade executor uses structured mock process command")
    func homebrewUpgradeExecutorUsesStructuredMockProcessCommand() async {
        let launcher = MockProcessLauncher(result: ProcessLaunchResult(
            exitCode: 0,
            stdout: "upgraded legacy\n",
            stderr: "",
        ), outputChunks: [
                ProcessOutputChunk(stream: .stdout, text: "==> Upgrading legacy\n"),
                ProcessOutputChunk(stream: .stderr, text: "warning: using cached download\n"),
        ])
        let executor = DefaultAppArchitectureUpgradeExecutor(processLauncher: launcher)
        let plan = await DefaultAppArchitectureUpgradePlanner().plan(for: appItem(
            name: "legacy",
            displayPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            source: .homebrew
        ))
        let progress = ProgressBox()

        let result = await executor.execute(plan: plan) { event in
            progress.append(event)
        }

        #expect(launcher.calls == [
            MockProcessLauncher.Call(executable: "brew", arguments: ["upgrade", "legacy"]),
        ])
        #expect(progress.values == [
            AppArchitectureUpgradeProgress(
                command: "brew upgrade legacy",
                stream: .stdout,
                text: "==> Upgrading legacy\n"
            ),
            AppArchitectureUpgradeProgress(
                command: "brew upgrade legacy",
                stream: .stderr,
                text: "warning: using cached download\n"
            ),
        ])
        #expect(result.status == .succeeded)
        #expect(result.commands == ["brew upgrade legacy"])
        #expect(result.stdoutSummary.contains("upgraded legacy"))
    }

    @Test("Homebrew upgrade executor reports process failure")
    func homebrewUpgradeExecutorReportsProcessFailure() async {
        let launcher = MockProcessLauncher(result: ProcessLaunchResult(
            exitCode: 42,
            stdout: "",
            stderr: "formula unavailable"
        ))
        let executor = DefaultAppArchitectureUpgradeExecutor(processLauncher: launcher)
        let plan = AppArchitectureUpgradePlan(
            status: .upgradeAvailable,
            source: .homebrew,
            packageIdentity: "legacy",
            displayCommands: ["brew upgrade legacy"],
            executableCommands: [["brew", "upgrade", "legacy"]],
            requiresSudo: false,
            confidence: .high,
            postCheckPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy"
        )

        let result = await executor.execute(plan: plan)

        #expect(result.status == .failed(exitCode: 42))
        #expect(result.stderrSummary.contains("formula unavailable"))
    }

    @Test("Homebrew migration executor runs native install before Intel uninstall")
    func homebrewMigrationExecutorRunsNativeInstallBeforeIntelUninstall() async {
        let launcher = MockProcessLauncher(results: [
            ProcessLaunchResult(exitCode: 0, stdout: "installed native\n", stderr: ""),
            ProcessLaunchResult(exitCode: 0, stdout: "uninstalled intel\n", stderr: ""),
        ])
        let executor = DefaultAppArchitectureUpgradeExecutor(processLauncher: launcher)
        let plan = await DefaultAppArchitectureUpgradePlanner().plan(for: appItem(
            name: "aliyun-cli",
            displayPath: "/usr/local/Cellar/aliyun-cli/3.0.90/bin/aliyun",
            source: .homebrew
        ))

        let result = await executor.execute(plan: plan)

        #expect(launcher.calls == [
            MockProcessLauncher.Call(executable: "/opt/homebrew/bin/brew", arguments: ["install", "aliyun-cli"]),
            MockProcessLauncher.Call(executable: "/usr/local/bin/brew", arguments: ["uninstall", "aliyun-cli"]),
        ])
        #expect(result.status == .succeeded)
        #expect(result.commands == [
            "/opt/homebrew/bin/brew install aliyun-cli",
            "/usr/local/bin/brew uninstall aliyun-cli",
        ])
        #expect(result.stdoutSummary.contains("installed native"))
        #expect(result.stdoutSummary.contains("uninstalled intel"))
    }

    @Test("Homebrew migration executor does not uninstall Intel formula when native install fails")
    func homebrewMigrationExecutorDoesNotUninstallIntelFormulaWhenNativeInstallFails() async {
        let launcher = MockProcessLauncher(results: [
            ProcessLaunchResult(exitCode: 1, stdout: "", stderr: "missing /opt/homebrew/bin/brew"),
            ProcessLaunchResult(exitCode: 0, stdout: "should not run", stderr: ""),
        ])
        let executor = DefaultAppArchitectureUpgradeExecutor(processLauncher: launcher)
        let plan = AppArchitectureUpgradePlan(
            status: .upgradeAvailable,
            source: .homebrew,
            packageIdentity: "aliyun-cli",
            displayCommands: [
                "/opt/homebrew/bin/brew install aliyun-cli",
                "/usr/local/bin/brew uninstall aliyun-cli",
            ],
            executableCommands: [
                ["/opt/homebrew/bin/brew", "install", "aliyun-cli"],
                ["/usr/local/bin/brew", "uninstall", "aliyun-cli"],
            ],
            requiresSudo: false
        )

        let result = await executor.execute(plan: plan)

        #expect(launcher.calls == [
            MockProcessLauncher.Call(executable: "/opt/homebrew/bin/brew", arguments: ["install", "aliyun-cli"]),
        ])
        #expect(result.status == .failed(exitCode: 1))
        #expect(result.stderrSummary.contains("missing /opt/homebrew/bin/brew"))
        #expect(!result.stdoutSummary.contains("should not run"))
    }

    @Test("Upgrade executor skips sudo or non-executable plans")
    func upgradeExecutorSkipsUnsafePlans() async {
        let launcher = MockProcessLauncher(result: ProcessLaunchResult(exitCode: 0, stdout: "", stderr: ""))
        let executor = DefaultAppArchitectureUpgradeExecutor(processLauncher: launcher)
        let sudoPlan = AppArchitectureUpgradePlan(
            status: .upgradeAvailable,
            source: .homebrew,
            displayCommands: ["brew upgrade legacy"],
            executableCommands: [["brew", "upgrade", "legacy"]],
            requiresSudo: true
        )
        let emptyPlan = AppArchitectureUpgradePlan(
            status: .upgradeAvailable,
            source: .homebrew,
            displayCommands: ["brew upgrade legacy"],
            executableCommands: [],
            requiresSudo: false
        )

        let sudoResult = await executor.execute(plan: sudoPlan)
        let emptyResult = await executor.execute(plan: emptyPlan)

        #expect(sudoResult.status == .skipped("当前计划需要 sudo，Axion 不自动执行。"))
        #expect(emptyResult.status == .skipped("当前计划没有可执行命令。"))
        #expect(launcher.calls.isEmpty)
    }

    @Test("Upgrade executor skips non-Homebrew executable plans")
    func upgradeExecutorSkipsNonHomebrewExecutablePlans() async {
        let launcher = MockProcessLauncher(result: ProcessLaunchResult(exitCode: 0, stdout: "", stderr: ""))
        let executor = DefaultAppArchitectureUpgradeExecutor(processLauncher: launcher)
        let plan = AppArchitectureUpgradePlan(
            status: .upgradeAvailable,
            source: .macPorts,
            displayCommands: ["port upgrade legacy"],
            executableCommands: [["port", "upgrade", "legacy"]],
            requiresSudo: false
        )

        let result = await executor.execute(plan: plan)

        #expect(result.status == .skipped("当前只支持 Homebrew 升级执行。"))
        #expect(launcher.calls.isEmpty)
    }

    @Test("Architecture detail analysis stores generated result and reuses cache")
    func architectureDetailAnalysisStoresAndReusesCache() async throws {
        let cacheDir = try makeTempDir("arch-analysis-cache")
        defer { cleanup(cacheDir) }
        let item = appItem(
            name: "legacy",
            displayPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            source: .homebrew
        )
        let cache = AppArchitectureDetailAnalysisCache(cacheDir: cacheDir.path)
        let generated = AppArchitectureDetailAnalysisService(
            config: AxionConfig(apiKey: "sk-test"),
            cache: cache,
            agentRunner: { prompt, _ in
                #expect(prompt.contains("name: legacy"))
                return #"{"summary":"legacy tool","primary_use":"archive work","category":"CLI","publisher":"Example","confidence":"high"}"#
            },
            now: { Date(timeIntervalSince1970: 0) }
        )

        let first = await generated.detail(for: item)

        #expect(first.analysisState == .generated)
        #expect(first.analysis?.summary == "legacy tool")
        #expect(first.analysis?.primaryUse == "archive work")

        let cached = AppArchitectureDetailAnalysisService(
            config: AxionConfig(apiKey: "sk-test"),
            cache: cache,
            agentRunner: { _, _ in
                throw TestError.unexpectedAgentCall
            }
        )
        let second = await cached.detail(for: item)

        #expect(second.analysisState == .cached)
        #expect(second.analysis?.summary == "legacy tool")
    }

    @Test("Architecture detail analysis reports parse failure")
    func architectureDetailAnalysisReportsParseFailure() async throws {
        let cacheDir = try makeTempDir("arch-analysis-failure")
        defer { cleanup(cacheDir) }
        let service = AppArchitectureDetailAnalysisService(
            config: AxionConfig(apiKey: "sk-test"),
            cache: AppArchitectureDetailAnalysisCache(cacheDir: cacheDir.path),
            agentRunner: { _, _ in "not json" }
        )

        let detail = await service.detail(for: appItem(
            name: "legacy",
            displayPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            source: .homebrew
        ))

        #expect(detail.analysis == nil)
        #expect(detail.analysisState == .failed("模型未返回可解析的 JSON"))
    }

    private func appItem(
        name: String,
        displayPath: String,
        executablePath: String? = nil,
        isSystemApp: Bool = false,
        source: AppArchitectureSource
    ) -> AppArchitectureItem {
        AppArchitectureItem(
            name: name,
            displayPath: displayPath,
            executablePath: executablePath ?? displayPath,
            architectures: [.x86_64],
            isSystemApp: isSystemApp,
            source: source
        )
    }

    private enum TestError: Error {
        case unexpectedAgentCall
    }

    private final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [AppArchitectureUpgradeProgress] = []

        var values: [AppArchitectureUpgradeProgress] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ value: AppArchitectureUpgradeProgress) {
            lock.lock()
            storage.append(value)
            lock.unlock()
        }
    }

    private final class MockProcessLauncher: ProcessLaunching, @unchecked Sendable {
        struct Call: Equatable {
            let executable: String
            let arguments: [String]
        }

        nonisolated(unsafe) var calls: [Call] = []
        let results: [ProcessLaunchResult]
        let outputChunks: [ProcessOutputChunk]

        init(result: ProcessLaunchResult, outputChunks: [ProcessOutputChunk] = []) {
            self.results = [result]
            self.outputChunks = outputChunks
        }

        init(results: [ProcessLaunchResult], outputChunks: [ProcessOutputChunk] = []) {
            self.results = results
            self.outputChunks = outputChunks
        }

        func run(
            executable: String,
            arguments: [String],
            onOutput: ProcessOutputHandler?
        ) async throws -> ProcessLaunchResult {
            calls.append(Call(executable: executable, arguments: arguments))
            for chunk in outputChunks {
                onOutput?(chunk)
            }
            return results.indices.contains(calls.count - 1)
                ? results[calls.count - 1]
                : results.last ?? ProcessLaunchResult(exitCode: 0, stdout: "", stderr: "")
        }
    }

    private func makeTempDir(_ label: String) throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("AppArchitectureScratch", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dir = root.appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }
}
