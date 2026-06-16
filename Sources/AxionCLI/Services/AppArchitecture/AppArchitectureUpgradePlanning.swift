import Foundation

enum AppArchitectureUpgradeStatus: Equatable, Sendable {
    case upgradeAvailable
    case manualOnly
    case unsupported
}

enum AppArchitectureUpgradeConfidence: String, Equatable, Sendable {
    case high
    case medium
    case low
}

struct AppArchitectureUpgradePlan: Equatable, Sendable {
    let status: AppArchitectureUpgradeStatus
    let source: AppArchitectureSource
    let packageIdentity: String?
    let displayCommands: [String]
    let executableCommands: [[String]]
    let requiresSudo: Bool
    let confidence: AppArchitectureUpgradeConfidence
    let postCheckPath: String?
    let notes: [String]

    init(
        status: AppArchitectureUpgradeStatus,
        source: AppArchitectureSource,
        packageIdentity: String? = nil,
        displayCommands: [String] = [],
        executableCommands: [[String]] = [],
        requiresSudo: Bool = false,
        confidence: AppArchitectureUpgradeConfidence = .low,
        postCheckPath: String? = nil,
        notes: [String] = []
    ) {
        self.status = status
        self.source = source
        self.packageIdentity = packageIdentity
        self.displayCommands = displayCommands
        self.executableCommands = executableCommands
        self.requiresSudo = requiresSudo
        self.confidence = confidence
        self.postCheckPath = postCheckPath
        self.notes = notes
    }
}

protocol AppArchitectureUpgradePlanning: Sendable {
    func plan(for item: AppArchitectureItem) async -> AppArchitectureUpgradePlan
}

struct DefaultAppArchitectureUpgradePlanner: AppArchitectureUpgradePlanning {
    private let homebrewCellarRoots: [String]

    init(homebrewCellarRoots: [String] = ["/opt/homebrew/Cellar", "/usr/local/Cellar"]) {
        self.homebrewCellarRoots = homebrewCellarRoots.map(Self.normalizedDirectory)
    }

    func plan(for item: AppArchitectureItem) async -> AppArchitectureUpgradePlan {
        if item.category == .unknown {
            return AppArchitectureUpgradePlan(
                status: .unsupported,
                source: item.source,
                confidence: .low,
                postCheckPath: item.executablePath ?? item.displayPath,
                notes: [
                    "未能识别 Mach-O 架构，无法生成可靠升级计划。",
                    "请先确认该路径是否为原生可执行文件或是否有读取权限。",
                ]
            )
        }

        switch item.source {
        case .homebrew:
            return homebrewPlan(for: item)
        case .macPorts:
            return AppArchitectureUpgradePlan(
                status: .manualOnly,
                source: item.source,
                requiresSudo: true,
                confidence: .medium,
                postCheckPath: item.executablePath ?? item.displayPath,
                notes: [
                    "MacPorts 项需要用户手动评估；MVP 不自动执行 sudo port。",
                    "可在终端自行确认可用版本后再升级，例如 port selfupdate / port upgrade。",
                ]
            )
        case .application where item.isSystemApp:
            return AppArchitectureUpgradePlan(
                status: .manualOnly,
                source: item.source,
                confidence: .medium,
                postCheckPath: item.executablePath ?? item.displayPath,
                notes: [
                    "系统应用应通过 macOS 系统更新处理。",
                    "Axion 不会对 /System/Applications 生成自动升级动作。",
                ]
            )
        case .application:
            return AppArchitectureUpgradePlan(
                status: .manualOnly,
                source: item.source,
                confidence: .medium,
                postCheckPath: item.executablePath ?? item.displayPath,
                notes: [
                    "直接安装的 App 需要通过厂商更新器、官网下载或 App 内更新处理。",
                    "MVP 不自动下载、安装或重装厂商 App。",
                ]
            )
        }
    }

    private func homebrewPlan(for item: AppArchitectureItem) -> AppArchitectureUpgradePlan {
        guard let identity = formulaIdentity(from: item.executablePath) ?? formulaIdentity(from: item.displayPath) else {
            return AppArchitectureUpgradePlan(
                status: .unsupported,
                source: item.source,
                confidence: .low,
                postCheckPath: item.executablePath ?? item.displayPath,
                notes: [
                    "未能从 Homebrew Cellar 路径识别 formula 名称。",
                    "当前只对安全的 Cellar formula 路径生成可确认执行计划。",
                ]
            )
        }

        if identity.cellarRoot == "/usr/local/Cellar" {
            let formula = identity.formula
            return AppArchitectureUpgradePlan(
                status: .upgradeAvailable,
                source: item.source,
                packageIdentity: formula,
                displayCommands: [
                    "/opt/homebrew/bin/brew install \(formula)",
                    "/usr/local/bin/brew uninstall \(formula)",
                ],
                executableCommands: [
                    ["/opt/homebrew/bin/brew", "install", formula],
                    ["/usr/local/bin/brew", "uninstall", formula],
                ],
                requiresSudo: false,
                confidence: .high,
                postCheckPath: item.executablePath ?? item.displayPath,
                notes: [
                    "/usr/local/Cellar 通常是 Intel Homebrew 前缀；brew upgrade 只会升级该前缀，不会迁移为 arm64。",
                    "迁移计划会先用 Apple Silicon Homebrew（/opt/homebrew）安装该 formula，安装成功后才卸载 /usr/local 的 Intel formula。",
                    "完成后需要确认 PATH 优先使用 /opt/homebrew/bin 中的原生版本。",
                ]
            )
        }

        let formula = identity.formula
        return AppArchitectureUpgradePlan(
            status: .upgradeAvailable,
            source: item.source,
            packageIdentity: formula,
            displayCommands: ["brew upgrade \(formula)"],
            executableCommands: [["brew", "upgrade", formula]],
            requiresSudo: false,
            confidence: .high,
            postCheckPath: item.executablePath ?? item.displayPath,
            notes: [
                "按 u 确认后会执行 Homebrew 升级；不会执行 sudo、port 或 mas。",
                "升级后需要重新扫描该路径确认是否提供 arm64/universal。",
            ]
        )
    }

    private func formulaIdentity(from rawPath: String?) -> (formula: String, cellarRoot: String)? {
        guard let rawPath, !rawPath.isEmpty else { return nil }
        let normalizedPath = Self.normalizedPath(rawPath)
        for root in homebrewCellarRoots {
            let prefix = root + "/"
            guard normalizedPath.hasPrefix(prefix) else { continue }
            let remainder = normalizedPath.dropFirst(prefix.count)
            guard let name = remainder.split(separator: "/", omittingEmptySubsequences: true).first else { continue }
            let formula = String(name)
            return Self.isSafeHomebrewFormulaName(formula) ? (formula, root) : nil
        }
        return nil
    }

    private static func isSafeHomebrewFormulaName(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.utf8.allSatisfy { byte in
            (48...57).contains(byte) ||
                (65...90).contains(byte) ||
                (97...122).contains(byte) ||
                byte == 43 ||
                byte == 45 ||
                byte == 46 ||
                byte == 64 ||
                byte == 95
        }
    }

    private static func normalizedDirectory(_ raw: String) -> String {
        normalizedPath(raw).withLeadingSlash
    }

    private static func normalizedPath(_ raw: String) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}

private extension String {
    var withLeadingSlash: String {
        hasPrefix("/") ? self : "/" + self
    }
}
