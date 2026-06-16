import Testing

@testable import AxionCLI

@Suite("App Architecture Selection Prompt")
struct AppArchitectureSelectionPromptTests {
    private struct MockUpgradePlanner: AppArchitectureUpgradePlanning {
        let plan: AppArchitectureUpgradePlan

        func plan(for _: AppArchitectureItem) async -> AppArchitectureUpgradePlan {
            plan
        }
    }

    private struct MockDetailProvider: AppArchitectureDetailProviding {
        let info: AppArchitectureDetailInfo

        func detail(for _: AppArchitectureItem) async -> AppArchitectureDetailInfo {
            info
        }
    }

    private final class CountingUpgradePlanner: AppArchitectureUpgradePlanning, @unchecked Sendable {
        nonisolated(unsafe) var callCount = 0
        let plan: AppArchitectureUpgradePlan

        init(plan: AppArchitectureUpgradePlan) {
            self.plan = plan
        }

        func plan(for _: AppArchitectureItem) async -> AppArchitectureUpgradePlan {
            callCount += 1
            return plan
        }
    }

    private final class MockUpgradeExecutor: AppArchitectureUpgradeExecuting, @unchecked Sendable {
        nonisolated(unsafe) var callCount = 0
        nonisolated(unsafe) var receivedPlans: [AppArchitectureUpgradePlan] = []
        let result: AppArchitectureUpgradeExecutionResult
        let progress: [AppArchitectureUpgradeProgress]

        init(
            result: AppArchitectureUpgradeExecutionResult = .successFixture(),
            progress: [AppArchitectureUpgradeProgress] = []
        ) {
            self.result = result
            self.progress = progress
        }

        func execute(
            plan: AppArchitectureUpgradePlan,
            onProgress: AppArchitectureUpgradeProgressHandler?
        ) async -> AppArchitectureUpgradeExecutionResult {
            callCount += 1
            receivedPlans.append(plan)
            for event in progress {
                onProgress?(event)
            }
            return result
        }
    }

    private struct MockPostUpgradeScanner: AppArchitecturePostUpgradeScanning {
        let item: AppArchitectureItem?

        func rescan(item _: AppArchitectureItem) async -> AppArchitectureItem? {
            item
        }
    }

    private final class RecordingArchitectureScanner: AppArchitectureScanning, @unchecked Sendable {
        nonisolated(unsafe) var calls: [AppArchitectureScanOptions] = []
        let result: AppArchitectureScanResult

        init(result: AppArchitectureScanResult) {
            self.result = result
        }

        func scan(options: AppArchitectureScanOptions) async -> AppArchitectureScanResult {
            calls.append(options)
            return result
        }
    }

    private final class OutputCapture {
        var text = ""

        var latestScreen: String {
            text.components(separatedBy: "\u{1B}[J").last ?? text
        }

        func write(_ value: String) {
            text += value
        }
    }

    private func item(
        _ name: String,
        path: String? = nil,
        architectures: Set<AppBinaryArchitecture> = [.x86_64],
        source: AppArchitectureSource = .application
    ) -> AppArchitectureItem {
        let displayPath = path ?? "/Applications/\(name).app"
        return AppArchitectureItem(
            name: name,
            displayPath: displayPath,
            executablePath: displayPath + "/Contents/MacOS/\(name)",
            architectures: architectures,
            isSystemApp: false,
            source: source
        )
    }

    private func result(_ items: [AppArchitectureItem]) -> AppArchitectureScanResult {
        AppArchitectureScanResult(
            options: AppArchitectureScanOptions(includeAllArchitectures: false, limit: 80),
            items: items,
            warnings: []
        )
    }

    @Test("enter opens architecture detail")
    func enterOpensDetail() async {
        let output = OutputCapture()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.down, .enter, .escape]),
            writeOutput: { output.write($0) }
        )

        #expect(await prompt.run(result: result([
            item("Slack"),
            item("Zoom", path: "/Applications/Zoom.app"),
        ])) == .cancelled)
        #expect(output.text.contains("软件架构候选"))
        #expect(output.text.contains("架构详情"))
        #expect(output.text.contains("Zoom"))
        #expect(output.text.contains("可执行文件"))
        #expect(output.text.contains("b 返回列表"))
    }

    @Test("b returns from detail to architecture list")
    func bReturnsFromDetailToList() async {
        let output = OutputCapture()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("b"), .down, .enter, .escape]),
            writeOutput: { output.write($0) }
        )

        #expect(await prompt.run(result: result([
            item("Slack"),
            item("Zoom"),
        ])) == .cancelled)
        #expect(output.text.contains("架构详情"))
        #expect(output.text.contains("▶ Zoom"))
    }

    @Test("down past first page scrolls architecture list")
    func downPastFirstPageScrollsList() async {
        let output = OutputCapture()
        let events = Array(repeating: KeyEvent.down, count: 20) + [.enter, .escape]
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader(events),
            writeOutput: { output.write($0) },
            maxItems: 20
        )
        let items = (1...25).map { index in
            item("Tool \(index)", path: "/opt/homebrew/Cellar/tool\(index)/bin/tool\(index)", source: .homebrew)
        }

        #expect(await prompt.run(result: result(items)) == .cancelled)
        #expect(output.text.contains("Tool 21"))
        #expect(output.text.contains("显示 2-21 / 25"))
    }

    @Test("non-TTY renders numbered list")
    func nonTTYListOnly() async {
        let output = OutputCapture()
        let planner = CountingUpgradePlanner(plan: homebrewPlan())
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: false,
            keyReader: nil,
            writeOutput: { output.write($0) },
            upgradePlanner: planner
        )

        #expect(await prompt.run(result: result([item("Slack")])) == .nonTTYListOnly)
        #expect(planner.callCount == 0)
        #expect(output.text.contains("1."))
        #expect(output.text.contains("Slack"))
        #expect(output.text.contains("非交互模式"))
        #expect(!output.text.contains("↑/↓"))
        #expect(!output.text.contains("升级状态"))
    }

    @Test("q cancels architecture prompt")
    func qCancelsPrompt() async {
        let output = OutputCapture()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.printable("q")]),
            writeOutput: { output.write($0) }
        )

        #expect(await prompt.run(result: result([item("Slack")])) == .cancelled)
        #expect(output.text.contains("Slack"))
        #expect(output.text.hasSuffix("\r\n"))
    }

    @Test("Ctrl-C cancels architecture prompt")
    func ctrlCCancelsPrompt() async {
        let output = OutputCapture()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.ctrl("c")]),
            writeOutput: { output.write($0) }
        )

        #expect(await prompt.run(result: result([item("Slack")])) == .cancelled)
        #expect(output.text.contains("Slack"))
        #expect(output.text.hasSuffix("\r\n"))
    }

    @Test("detail renders upgrade plan from planner")
    func detailRendersUpgradePlan() async {
        let output = OutputCapture()
        let plan = homebrewPlan()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: plan)
        )

        #expect(await prompt.run(result: result([
            item("legacy", path: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy", source: .homebrew),
        ])) == .cancelled)
        #expect(output.text.contains("升级状态: 可生成升级计划"))
        #expect(output.text.contains("包身份: legacy"))
        #expect(output.text.contains("升级命令: brew upgrade legacy"))
        #expect(output.text.contains("需要 sudo: 否"))
        #expect(output.text.contains("可用操作:"))
        #expect(output.text.contains("u 升级"))
        #expect(output.text.contains("升级: 按 u 确认并执行 brew upgrade legacy"))
        #expect(output.text.contains("卸载: 当前 /arch 不执行包卸载"))
    }

    @Test("u confirms and executes Homebrew upgrade")
    func uConfirmsAndExecutesHomebrewUpgrade() async {
        let output = OutputCapture()
        let upgradedItem = item(
            "legacy",
            path: "/opt/homebrew/Cellar/legacy/2.0/bin/legacy",
            architectures: [.arm64],
            source: .homebrew
        )
        let executor = MockUpgradeExecutor(progress: [
            AppArchitectureUpgradeProgress(
                command: "brew upgrade legacy",
                stream: .stdout,
                text: "==> Upgrading legacy\n==> Pouring legacy--2.0.arm64.bottle.tar.gz\n"
            ),
        ])
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("u"), .printable("y"), .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: homebrewPlan()),
            upgradeExecutor: executor,
            postUpgradeScanner: MockPostUpgradeScanner(item: upgradedItem)
        )

        #expect(await prompt.run(result: result([
            item("legacy", path: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy", source: .homebrew),
        ])) == .cancelled)
        #expect(executor.callCount == 1)
        #expect(executor.receivedPlans.first?.displayCommands == ["brew upgrade legacy"])
        #expect(output.text.contains("升级确认"))
        #expect(output.text.contains("将执行: brew upgrade legacy"))
        #expect(output.text.contains("升级执行中"))
        #expect(output.text.contains("最新输出:"))
        #expect(output.text.contains("stdout: ==> Upgrading legacy"))
        #expect(output.text.contains("stdout: ==> Pouring legacy--2.0.arm64.bottle.tar.gz"))
        #expect(output.text.contains("升级结果"))
        #expect(output.text.contains("命令状态: 成功"))
        #expect(output.text.contains("架构结果: 已达成目标（arm64）"))
        #expect(output.text.contains("升级前架构: x86_64"))
        #expect(output.text.contains("复扫后架构: arm64"))
    }

    @Test("b after successful upgrade rescans architecture list")
    func bAfterSuccessfulUpgradeRescansArchitectureList() async {
        let output = OutputCapture()
        let upgradedItem = item(
            "legacy",
            path: "/opt/homebrew/Cellar/legacy/2.0/bin/legacy",
            architectures: [.arm64],
            source: .homebrew
        )
        let remainingIntelItem = item(
            "remaining",
            path: "/opt/homebrew/Cellar/remaining/1.0/bin/remaining",
            source: .homebrew
        )
        let listScanner = RecordingArchitectureScanner(result: result([
            upgradedItem,
            remainingIntelItem,
        ]))
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("u"), .printable("y"), .printable("b"), .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: homebrewPlan()),
            upgradeExecutor: MockUpgradeExecutor(),
            postUpgradeScanner: MockPostUpgradeScanner(item: upgradedItem),
            listScanner: listScanner
        )

        #expect(await prompt.run(result: result([
            item("legacy", path: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy", source: .homebrew),
        ])) == .cancelled)
        #expect(listScanner.calls == [AppArchitectureScanOptions(includeAllArchitectures: false, limit: 80)])
        #expect(output.text.contains("升级结果"))
        #expect(output.latestScreen.contains("软件架构候选"))
        #expect(output.latestScreen.contains("remaining"))
        #expect(!output.latestScreen.contains("legacy"))
    }

    @Test("list redraw after upgrade keeps refreshed architecture list")
    func listRedrawAfterUpgradeKeepsRefreshedArchitectureList() async {
        let output = OutputCapture()
        let upgradedItem = item(
            "legacy",
            path: "/opt/homebrew/Cellar/legacy/2.0/bin/legacy",
            architectures: [.arm64],
            source: .homebrew
        )
        let remainingOne = item(
            "remaining-one",
            path: "/opt/homebrew/Cellar/remaining-one/1.0/bin/remaining-one",
            source: .homebrew
        )
        let remainingTwo = item(
            "remaining-two",
            path: "/opt/homebrew/Cellar/remaining-two/1.0/bin/remaining-two",
            source: .homebrew
        )
        let allArchitectureScanResult = AppArchitectureScanResult(
            options: AppArchitectureScanOptions(includeAllArchitectures: true, limit: 80),
            items: [
                upgradedItem,
                remainingOne,
                remainingTwo,
            ],
            warnings: []
        )
        let listScanner = RecordingArchitectureScanner(result: allArchitectureScanResult)
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("u"), .printable("y"), .printable("b"), .down, .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: homebrewPlan()),
            upgradeExecutor: MockUpgradeExecutor(),
            postUpgradeScanner: MockPostUpgradeScanner(item: upgradedItem),
            listScanner: listScanner
        )

        #expect(await prompt.run(result: result([
            item("legacy", path: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy", source: .homebrew),
            item("stale-old", path: "/opt/homebrew/Cellar/stale-old/1.0/bin/stale-old", source: .homebrew),
        ])) == .cancelled)
        #expect(listScanner.calls == [AppArchitectureScanOptions(includeAllArchitectures: false, limit: 80)])
        #expect(output.latestScreen.contains("软件架构候选"))
        #expect(output.latestScreen.contains("remaining-one"))
        #expect(output.latestScreen.contains("▶ remaining-two"))
        #expect(!output.latestScreen.contains("legacy"))
        #expect(!output.latestScreen.contains("stale-old"))
    }

    @Test("b after failed upgrade does not rescan architecture list")
    func bAfterFailedUpgradeDoesNotRescanArchitectureList() async {
        let output = OutputCapture()
        let listScanner = RecordingArchitectureScanner(result: result([
            item("remaining", path: "/opt/homebrew/Cellar/remaining/1.0/bin/remaining", source: .homebrew),
        ]))
        let failedExecutor = MockUpgradeExecutor(result: AppArchitectureUpgradeExecutionResult(
            status: .failed(exitCode: 1),
            commands: ["brew upgrade legacy"],
            stdoutSummary: "-",
            stderrSummary: "failed"
        ))
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("u"), .printable("y"), .printable("b"), .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: homebrewPlan()),
            upgradeExecutor: failedExecutor,
            postUpgradeScanner: MockPostUpgradeScanner(item: nil),
            listScanner: listScanner
        )

        #expect(await prompt.run(result: result([
            item("legacy", path: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy", source: .homebrew),
        ])) == .cancelled)
        #expect(listScanner.calls.isEmpty)
        #expect(output.text.contains("命令状态: 失败（退出码 1）"))
        #expect(output.latestScreen.contains("软件架构候选"))
        #expect(output.latestScreen.contains("legacy"))
    }

    @Test("u confirms and executes Intel Homebrew migration")
    func uConfirmsAndExecutesIntelHomebrewMigration() async {
        let output = OutputCapture()
        let migratedItem = item(
            "aliyun-cli",
            path: "/opt/homebrew/Cellar/aliyun-cli/3.0.91/bin/aliyun",
            architectures: [.arm64],
            source: .homebrew
        )
        let plan = intelHomebrewMigrationPlan()
        let executor = MockUpgradeExecutor(
            result: AppArchitectureUpgradeExecutionResult(
                status: .succeeded,
                commands: plan.displayCommands,
                stdoutSummary: "installed native\nuninstalled intel",
                stderrSummary: "-"
            ),
            progress: [
                AppArchitectureUpgradeProgress(
                    command: "/opt/homebrew/bin/brew install aliyun-cli",
                    stream: .stdout,
                    text: "==> Installing aliyun-cli\n"
                ),
                AppArchitectureUpgradeProgress(
                    command: "/usr/local/bin/brew uninstall aliyun-cli",
                    stream: .stdout,
                    text: "Uninstalling /usr/local/Cellar/aliyun-cli/3.0.90...\n"
                ),
            ]
        )
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("u"), .printable("y"), .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: plan),
            upgradeExecutor: executor,
            postUpgradeScanner: MockPostUpgradeScanner(item: migratedItem)
        )

        #expect(await prompt.run(result: result([
            item(
                "aliyun-cli",
                path: "/usr/local/Cellar/aliyun-cli/3.0.90/bin/aliyun",
                source: .homebrew
            ),
        ])) == .cancelled)
        #expect(executor.callCount == 1)
        #expect(executor.receivedPlans.first?.displayCommands == [
            "/opt/homebrew/bin/brew install aliyun-cli",
            "/usr/local/bin/brew uninstall aliyun-cli",
        ])
        #expect(output.text.contains("将执行: /opt/homebrew/bin/brew install aliyun-cli"))
        #expect(output.text.contains("          /usr/local/bin/brew uninstall aliyun-cli"))
        #expect(output.text.contains("成功后才卸载 /usr/local Intel formula"))
        #expect(output.text.contains("stdout: ==> Installing aliyun-cli"))
        #expect(output.text.contains("stdout: Uninstalling /usr/local/Cellar/aliyun-cli/3.0.90"))
        #expect(output.text.contains("架构结果: 已达成目标（arm64）"))
        #expect(output.text.contains("复扫路径: /opt/homebrew/Cellar/aliyun-cli/3.0.91/bin/aliyun"))
    }

    @Test("u cancellation does not execute Homebrew upgrade")
    func uCancellationDoesNotExecuteHomebrewUpgrade() async {
        let output = OutputCapture()
        let executor = MockUpgradeExecutor()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("u"), .printable("n"), .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: homebrewPlan()),
            upgradeExecutor: executor,
            postUpgradeScanner: MockPostUpgradeScanner(item: nil)
        )

        #expect(await prompt.run(result: result([
            item("legacy", path: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy", source: .homebrew),
        ])) == .cancelled)
        #expect(executor.callCount == 0)
        #expect(output.text.contains("升级确认"))
        #expect(!output.text.contains("升级执行中"))
    }

    @Test("u is ignored when upgrade plan is manual only")
    func uIgnoredWhenUpgradePlanIsManualOnly() async {
        let output = OutputCapture()
        let executor = MockUpgradeExecutor()
        let manualPlan = AppArchitectureUpgradePlan(
            status: .manualOnly,
            source: .application,
            confidence: .medium,
            postCheckPath: "/Applications/LegacyApp.app/Contents/MacOS/LegacyApp",
            notes: ["直接安装的 App 需要通过厂商更新器处理。"]
        )
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .printable("u"), .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: manualPlan),
            upgradeExecutor: executor
        )

        #expect(await prompt.run(result: result([item("LegacyApp")])) == .cancelled)
        #expect(executor.callCount == 0)
        #expect(!output.text.contains("升级确认"))
        #expect(!output.text.contains("u 升级"))
    }

    @Test("enter in app detail requests uninstall review")
    func enterInAppDetailRequestsUninstallReview() async {
        let output = OutputCapture()
        let legacyApp = item("LegacyApp")
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .enter]),
            writeOutput: { output.write($0) }
        )

        #expect(await prompt.run(result: result([legacyApp])) == .requestAppUninstall(legacyApp))
        #expect(output.text.contains("架构详情"))
        #expect(output.text.contains("Enter 卸载审核"))
        #expect(output.text.contains("卸载: 按 Enter 直接进入现有卸载审核流程"))
        #expect(output.text.hasSuffix("\r\n"))
    }

    @Test("enter in package detail does not request uninstall review")
    func enterInPackageDetailDoesNotRequestUninstallReview() async {
        let output = OutputCapture()
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .enter, .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: homebrewPlan())
        )

        #expect(await prompt.run(result: result([
            item("legacy", path: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy", source: .homebrew),
        ])) == .cancelled)
        #expect(output.text.contains("架构详情"))
        #expect(!output.text.contains("Enter 卸载审核"))
        #expect(output.text.contains("卸载: 当前 /arch 不执行包卸载"))
    }

    @Test("detail renders agent analysis from provider")
    func detailRendersAgentAnalysis() async {
        let output = OutputCapture()
        let analysis = AppAgentAnalysis(
            summary: "legacy 是一个命令行压缩工具。",
            primaryUse: "处理归档文件",
            category: "Developer Tool",
            publisher: "Example Project",
            confidence: "high",
            analyzedAt: "2026-06-16T00:00:00Z"
        )
        let prompt = AppArchitectureSelectionPrompt(
            isTTY: true,
            keyReader: MockKeyReader([.enter, .escape]),
            writeOutput: { output.write($0) },
            upgradePlanner: MockUpgradePlanner(plan: homebrewPlan()),
            detailProvider: MockDetailProvider(info: AppArchitectureDetailInfo(
                analysis: analysis,
                analysisState: .generated
            ))
        )

        #expect(await prompt.run(result: result([
            item("legacy", path: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy", source: .homebrew),
        ])) == .cancelled)
        #expect(output.text.contains("Agent 分析: 分析中"))
        #expect(output.text.contains("Agent 分析（新生成）"))
        #expect(output.text.contains("legacy 是一个命令行压缩工具"))
        #expect(output.text.contains("主要作用: 处理归档文件"))
        #expect(output.text.contains("厂商/项目: Example Project"))
    }

    private func homebrewPlan() -> AppArchitectureUpgradePlan {
        AppArchitectureUpgradePlan(
            status: .upgradeAvailable,
            source: .homebrew,
            packageIdentity: "legacy",
            displayCommands: ["brew upgrade legacy"],
            executableCommands: [["brew", "upgrade", "legacy"]],
            requiresSudo: false,
            confidence: .high,
            postCheckPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            notes: ["按 u 确认后会执行 Homebrew 升级。"]
        )
    }

    private func intelHomebrewMigrationPlan() -> AppArchitectureUpgradePlan {
        AppArchitectureUpgradePlan(
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
            requiresSudo: false,
            confidence: .high,
            postCheckPath: "/usr/local/Cellar/aliyun-cli/3.0.90/bin/aliyun",
            notes: [
                "/usr/local/Cellar 通常是 Intel Homebrew 前缀；brew upgrade 只会升级该前缀，不会迁移为 arm64。",
                "迁移计划会先用 Apple Silicon Homebrew（/opt/homebrew）安装该 formula，安装成功后才卸载 /usr/local 的 Intel formula。",
            ]
        )
    }
}

private extension AppArchitectureUpgradeExecutionResult {
    static func successFixture() -> AppArchitectureUpgradeExecutionResult {
        AppArchitectureUpgradeExecutionResult(
            status: .succeeded,
            commands: ["brew upgrade legacy"],
            stdoutSummary: "upgraded legacy",
            stderrSummary: "-"
        )
    }
}
