import Foundation
import Testing

@testable import AxionCLI

@Suite("App Architecture Scan Service")
struct AppArchitectureScanServiceTests {
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

    private func makeApp(root: URL, name: String, executableData: Data) throws -> URL {
        let app = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent(name)
        try executableData.write(to: executable)

        let plist: [String: Any] = [
            "CFBundleExecutable": name,
            "CFBundleIdentifier": "com.example.\(name.lowercased())",
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    @Test("Mach-O reader detects thin Intel and fat universal binaries")
    func machOReaderDetectsArchitectures() {
        #expect(MachOArchitectureReader.architectures(in: thinMachO(cpu: 0x01000007)) == [.x86_64])
        #expect(MachOArchitectureReader.architectures(in: thinMachO(cpu: 0x0100000c)) == [.arm64])
        #expect(MachOArchitectureReader.architectures(in: fatMachO(cpus: [0x01000007, 0x0100000c])) == [.x86_64, .arm64])
        #expect(MachOArchitectureReader.architectures(in: Data(repeating: 0, count: 32)).isEmpty)
    }

    @Test("scanner combines apps, Homebrew packages, and MacPorts packages")
    func scannerCombinesAppsAndPackages() async throws {
        let root = try makeTempDir("combined")
        defer { cleanup(root) }

        let appsRoot = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appsRoot, withIntermediateDirectories: true)
        _ = try makeApp(root: appsRoot, name: "OldApp", executableData: thinMachO(cpu: 0x01000007))
        _ = try makeApp(root: appsRoot, name: "NativeApp", executableData: thinMachO(cpu: 0x0100000c))
        _ = try makeApp(root: appsRoot, name: "UniversalApp", executableData: fatMachO(cpus: [0x01000007, 0x0100000c]))

        let brewPrefix = root.appendingPathComponent("brew", isDirectory: true)
        let brewBin = brewPrefix.appendingPathComponent("bin", isDirectory: true)
        let brewExecutable = brewPrefix
            .appendingPathComponent("Cellar", isDirectory: true)
            .appendingPathComponent("legacy", isDirectory: true)
            .appendingPathComponent("1.0", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: brewExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: brewBin, withIntermediateDirectories: true)
        try thinMachO(cpu: 0x01000007).write(to: brewExecutable)
        try FileManager.default.createSymbolicLink(
            at: brewBin.appendingPathComponent("legacy"),
            withDestinationURL: brewExecutable
        )

        let portsRoot = root.appendingPathComponent("macports", isDirectory: true)
        let portsBin = portsRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: portsBin, withIntermediateDirectories: true)
        try Data().write(to: portsBin.appendingPathComponent("port"))
        try thinMachO(cpu: 0x01000007).write(to: portsBin.appendingPathComponent("legacy-port"))

        let service = AppArchitectureScanService(
            appRootProvider: { _ in [(appsRoot, false)] },
            homebrewPrefixes: [brewPrefix.path],
            macPortsRoot: portsRoot.path
        )

        let result = await service.scan(options: AppArchitectureScanOptions(includeAllArchitectures: true))

        #expect(result.totalCount == 5)
        #expect(result.intelCount == 3)
        #expect(result.appleSiliconCount == 1)
        #expect(result.universalCount == 1)
        #expect(result.items.map(\.name).contains("legacy"))
        #expect(result.items.map(\.name).contains("legacy-port"))
    }

    @Test("result defaults to visible Intel-only items")
    func resultDefaultsToIntelOnlyVisibleItems() {
        let intel = AppArchitectureItem(
            name: "Old",
            displayPath: "/Applications/Old.app",
            executablePath: "/Applications/Old.app/Contents/MacOS/Old",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .application
        )
        let native = AppArchitectureItem(
            name: "Native",
            displayPath: "/Applications/Native.app",
            executablePath: "/Applications/Native.app/Contents/MacOS/Native",
            architectures: [.arm64],
            isSystemApp: false,
            source: .application
        )
        let result = AppArchitectureScanResult(
            options: AppArchitectureScanOptions(),
            items: [intel, native],
            warnings: []
        )

        #expect(result.visibleItems() == [intel])
        #expect(result.visibleTotalCount() == 1)
    }

    @Test("formatter renders summary and hides non-risk items by default")
    func formatterRendersRiskFocusedOutput() {
        let intel = AppArchitectureItem(
            name: "Old",
            displayPath: "/Applications/Old.app",
            executablePath: "/Applications/Old.app/Contents/MacOS/Old",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .application
        )
        let native = AppArchitectureItem(
            name: "Native",
            displayPath: "/Applications/Native.app",
            executablePath: "/Applications/Native.app/Contents/MacOS/Native",
            architectures: [.arm64],
            isSystemApp: false,
            source: .application
        )
        let result = AppArchitectureScanResult(
            options: AppArchitectureScanOptions(),
            items: [intel, native],
            warnings: []
        )

        let output = AppArchitectureFormatter.render(result)

        #expect(output.contains("Intel-only 1"))
        #expect(output.contains("Old"))
        #expect(!output.contains("Native.app"))
        #expect(output.contains("--all"))
        #expect(!output.contains("升级状态"))
        #expect(!output.contains("brew upgrade"))
    }

    @Test("formatter renders upgrade plan only in detail")
    func formatterRendersUpgradePlanOnlyInDetail() {
        let item = AppArchitectureItem(
            name: "legacy",
            displayPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            executablePath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .homebrew
        )
        let plan = AppArchitectureUpgradePlan(
            status: .upgradeAvailable,
            source: .homebrew,
            packageIdentity: "legacy",
            displayCommands: ["brew upgrade legacy", "brew test legacy"],
            executableCommands: [["brew", "upgrade", "legacy"]],
            requiresSudo: false,
            confidence: .high,
            postCheckPath: item.executablePath,
            notes: ["按 u 确认后会执行 Homebrew 升级。"]
        )

        let detail = AppArchitectureFormatter.renderDetail(item, upgradePlan: plan)
        let table = AppArchitectureFormatter.render(AppArchitectureScanResult(
            options: AppArchitectureScanOptions(),
            items: [item],
            warnings: []
        ))

        #expect(detail.contains("升级状态: 可生成升级计划"))
        #expect(detail.contains("包身份: legacy"))
        #expect(detail.contains("升级命令: brew upgrade legacy"))
        #expect(detail.contains("            brew test legacy"))
        #expect(!detail.contains("        : brew test legacy"))
        #expect(detail.contains("需要 sudo: 否"))
        #expect(detail.contains("可用操作:"))
        #expect(detail.contains("架构详情  u 升级"))
        #expect(detail.contains("升级: 按 u 确认并执行 brew upgrade legacy"))
        #expect(detail.contains("卸载: 当前 /arch 不执行包卸载"))
        #expect(!table.contains("升级状态"))
        #expect(!table.contains("brew upgrade"))
    }

    @Test("formatter renders Intel Homebrew migration confirmation")
    func formatterRendersIntelHomebrewMigrationConfirmation() {
        let item = AppArchitectureItem(
            name: "aliyun-cli",
            displayPath: "/usr/local/Cellar/aliyun-cli/3.0.90/bin/aliyun",
            executablePath: "/usr/local/Cellar/aliyun-cli/3.0.90/bin/aliyun",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .homebrew
        )
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
            requiresSudo: false,
            confidence: .high,
            postCheckPath: item.executablePath,
            notes: ["安装成功后才卸载 /usr/local 的 Intel formula。"]
        )

        let detail = AppArchitectureFormatter.renderDetail(item, upgradePlan: plan)
        let confirmation = AppArchitectureFormatter.renderUpgradeConfirmation(item: item, plan: plan)

        #expect(detail.contains("架构详情  u 升级"))
        #expect(detail.contains("升级命令: /opt/homebrew/bin/brew install aliyun-cli"))
        #expect(detail.contains("            /usr/local/bin/brew uninstall aliyun-cli"))
        #expect(detail.contains("升级: 按 u 确认并按顺序执行上方 Homebrew 命令"))
        #expect(confirmation.contains("将执行: /opt/homebrew/bin/brew install aliyun-cli"))
        #expect(confirmation.contains("          /usr/local/bin/brew uninstall aliyun-cli"))
        #expect(confirmation.contains("安装 Apple Silicon Homebrew formula"))
        #expect(confirmation.contains("成功后才卸载 /usr/local Intel formula"))
        #expect(confirmation.contains("不会执行 sudo、port、mas 或手动删除文件"))
        #expect(!confirmation.contains("不会执行 sudo、port、mas 或卸载"))
    }

    @Test("formatter renders app uninstall route in architecture detail")
    func formatterRendersAppUninstallRouteInDetail() {
        let item = AppArchitectureItem(
            name: "LegacyApp",
            displayPath: "/Applications/LegacyApp.app",
            executablePath: "/Applications/LegacyApp.app/Contents/MacOS/LegacyApp",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .application
        )
        let plan = AppArchitectureUpgradePlan(
            status: .manualOnly,
            source: .application,
            confidence: .medium,
            postCheckPath: item.executablePath,
            notes: ["直接安装的 App 需要通过厂商更新器处理。"]
        )

        let detail = AppArchitectureFormatter.renderDetail(item, upgradePlan: plan)

        #expect(detail.contains("可用操作:"))
        #expect(detail.contains("升级: 需手动处理"))
        #expect(detail.contains("架构详情  Enter 卸载审核"))
        #expect(detail.contains("卸载: 按 Enter 直接进入现有卸载审核流程"))
    }

    @Test("formatter reports command success but architecture not fixed")
    func formatterReportsCommandSuccessButArchitectureNotFixed() {
        let before = AppArchitectureItem(
            name: "aliyun-cli",
            displayPath: "/usr/local/Cellar/aliyun-cli/3.0.89/bin/aliyun",
            executablePath: "/usr/local/Cellar/aliyun-cli/3.0.89/bin/aliyun",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .homebrew
        )
        let after = AppArchitectureItem(
            name: "aliyun-cli",
            displayPath: "/usr/local/Cellar/aliyun-cli/3.0.90/bin/aliyun",
            executablePath: "/usr/local/Cellar/aliyun-cli/3.0.90/bin/aliyun",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .homebrew
        )
        let result = AppArchitectureUpgradeExecutionResult(
            status: .succeeded,
            commands: ["brew upgrade aliyun-cli"],
            stdoutSummary: "upgraded",
            stderrSummary: "-"
        )

        let output = AppArchitectureFormatter.renderUpgradeResult(
            item: before,
            before: before,
            after: after,
            result: result
        )

        #expect(output.contains("命令状态: 成功"))
        #expect(output.contains("架构结果: 未达成目标（仍为 Intel-only）"))
        #expect(output.contains("brew 命令成功不等于架构已修复"))
        #expect(output.contains("/usr/local Intel Homebrew 前缀"))
    }

    @Test("formatter reports architecture upgrade target achieved")
    func formatterReportsArchitectureUpgradeTargetAchieved() {
        let before = AppArchitectureItem(
            name: "legacy",
            displayPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            executablePath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .homebrew
        )
        let after = AppArchitectureItem(
            name: "legacy",
            displayPath: "/opt/homebrew/Cellar/legacy/2.0/bin/legacy",
            executablePath: "/opt/homebrew/Cellar/legacy/2.0/bin/legacy",
            architectures: [.arm64],
            isSystemApp: false,
            source: .homebrew
        )
        let result = AppArchitectureUpgradeExecutionResult(
            status: .succeeded,
            commands: ["brew upgrade legacy"],
            stdoutSummary: "upgraded",
            stderrSummary: "-"
        )

        let output = AppArchitectureFormatter.renderUpgradeResult(
            item: before,
            before: before,
            after: after,
            result: result
        )

        #expect(output.contains("命令状态: 成功"))
        #expect(output.contains("架构结果: 已达成目标（arm64）"))
        #expect(!output.contains("brew 命令成功不等于架构已修复"))
    }

    @Test("formatter builds app uninstall review request from architecture detail")
    func formatterBuildsAppUninstallReviewRequestFromArchitectureDetail() throws {
        let item = AppArchitectureItem(
            name: "Bad\nApp\u{1B}[31m",
            displayPath: "/opt/apps/Bad.app",
            executablePath: "/opt/apps/Bad.app/Contents/MacOS/Bad",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .application
        )

        let request = try #require(AppArchitectureFormatter.appUninstallRequest(for: item))
        let jsonPrefix = "scan_app_uninstall 参数 JSON: "
        let json = try #require(request.components(separatedBy: jsonPrefix).last)
        let data = try #require(json.data(using: .utf8))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let roots = try #require(payload["search_roots"] as? [String])
        let selected = try #require(payload["selected_app"] as? [String: String])

        #expect(request.contains("不可信 /arch 元数据"))
        #expect(request.contains("不要直接调用 execute_app_uninstall"))
        #expect(payload["query"] as? String == "Bad App")
        #expect(payload["mode"] as? String == "uninstall_with_support_review")
        #expect(roots.contains("/Applications"))
        #expect(roots.contains("~/Applications"))
        #expect(roots.contains("/opt/apps"))
        #expect(selected["bundle_path"] == "/opt/apps/Bad.app")
        #expect(!request.contains("\u{1B}"))
        #expect(!request.contains("[31m"))
        #expect(!request.contains("Bad\nApp"))
    }

    @Test("formatter does not build uninstall request for system apps or packages")
    func formatterDoesNotBuildUninstallRequestForSystemAppsOrPackages() {
        let systemApp = AppArchitectureItem(
            name: "System Settings",
            displayPath: "/System/Applications/System Settings.app",
            executablePath: "/System/Applications/System Settings.app/Contents/MacOS/System Settings",
            architectures: [.arm64],
            isSystemApp: true,
            source: .application
        )
        let package = AppArchitectureItem(
            name: "legacy",
            displayPath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            executablePath: "/opt/homebrew/Cellar/legacy/1.0/bin/legacy",
            architectures: [.x86_64],
            isSystemApp: false,
            source: .homebrew
        )

        #expect(AppArchitectureFormatter.appUninstallRequest(for: systemApp) == nil)
        #expect(AppArchitectureFormatter.appUninstallRequest(for: package) == nil)
    }

    @Test("slash option parser accepts filter and flags")
    func slashOptionParser() throws {
        let options = try #require(AppArchitectureFormatter.parseOptions(
            argument: "visual studio --all --system --packages-only --limit 12"
        ))

        #expect(options.filter == "visual studio")
        #expect(options.includeAllArchitectures)
        #expect(options.includeSystemApps)
        #expect(options.scope == .packagesOnly)
        #expect(options.limit == 12)
        #expect(AppArchitectureFormatter.parseOptions(argument: "--apps-only --packages-only") == nil)
        #expect(AppArchitectureFormatter.parseOptions(argument: "--unknown") == nil)
    }

    private func thinMachO(cpu: UInt32) -> Data {
        var data = Data()
        appendUInt32LE(0xfeedfacf, to: &data)
        appendUInt32LE(cpu, to: &data)
        data.append(Data(repeating: 0, count: 64))
        return data
    }

    private func fatMachO(cpus: [UInt32]) -> Data {
        var data = Data()
        appendUInt32BE(0xcafebabe, to: &data)
        appendUInt32BE(UInt32(cpus.count), to: &data)
        for cpu in cpus {
            appendUInt32BE(cpu, to: &data)
            appendUInt32BE(0, to: &data)
            appendUInt32BE(0, to: &data)
            appendUInt32BE(0, to: &data)
            appendUInt32BE(0, to: &data)
        }
        return data
    }

    private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    private func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }
}
