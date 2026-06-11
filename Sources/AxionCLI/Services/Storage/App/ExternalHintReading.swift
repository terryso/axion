import Foundation

import AxionCore

/// 外部卸载提示读取抽象（Protocol，测试注入 `MockExternalHintReader` 用）。
///
/// **只读 + best-effort**：探测 pkg receipts / Homebrew cask metadata，产出 `ExternalUninstallHint`
/// 仅供展示。**绝不执行**（AC #11）：任何 hint 都不改变 Axion 的风险分级与确认流程；探测失败
/// 优雅降级为空。**禁止** spawn 任何进程（无 `sudo` / `pkgutil --forget` / `brew uninstall`）。
protocol ExternalHintReading: Sendable {
    func read(for app: AppCandidate) -> [ExternalUninstallHint]
}

/// 外部卸载提示读取实现：pkg receipts + Homebrew cask 探测（全 `try?`，绝不 spawn 进程）。
///
/// - pkg receipts：`/var/db/receipts/` 下以 bundle id 为键的 `.plist` / `.bom`（安装收据）。
/// - Homebrew cask：`/opt/homebrew/Caskroom/<cask>` 目录名与 displayName 归一后匹配。
///
/// 两者均为只读文件系统探测，失败返回空，不阻塞 App bundle 卸载。
final class ExternalHintReader: ExternalHintReading, Sendable {

    private static let receiptsDir = "/var/db/receipts"
    private static let caskroomDir = "/opt/homebrew/Caskroom"

    init() {}

    func read(for app: AppCandidate) -> [ExternalUninstallHint] {
        var hints: [ExternalUninstallHint] = []
        hints.append(contentsOf: readPkgReceipts(for: app))
        hints.append(contentsOf: readHomebrewCask(for: app))
        return hints
    }

    /// pkg receipts 探测（best-effort，只读）。
    private func readPkgReceipts(for app: AppCandidate) -> [ExternalUninstallHint] {
        let bundleId = app.bundleIdentifier
        guard !bundleId.isEmpty else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: Self.receiptsDir) else { return [] }
        // 收据文件名形如 `<bundleId>.plist` / `<bundleId>.bom`；键控前缀匹配，避免误报。
        let matches = entries.filter { $0.hasPrefix(bundleId + ".") }
        guard !matches.isEmpty else { return [] }
        let paths = matches.map { "\(Self.receiptsDir)/\($0)" }
        return [ExternalUninstallHint(
            source: "pkg_receipt",
            detail: "Found \(matches.count) pkg receipt(s) referencing \(bundleId)",
            paths: paths,
            confidence: .medium
        )]
    }

    /// Homebrew cask 探测（best-effort，只读 Caskroom 目录名）。
    private func readHomebrewCask(for app: AppCandidate) -> [ExternalUninstallHint] {
        let lowered = app.displayName.lowercased().replacingOccurrences(of: " ", with: "-")
        let normalized = String(lowered.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" })
        guard !normalized.isEmpty else { return [] }
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: Self.caskroomDir) else { return [] }
        let matches = entries.filter { $0.lowercased() == normalized }
        guard !matches.isEmpty else { return [] }
        return [ExternalUninstallHint(
            source: "homebrew_cask",
            detail: "Homebrew Caskroom contains \(matches.joined(separator: ", "))",
            paths: matches.map { "\(Self.caskroomDir)/\($0)" },
            confidence: .low
        )]
    }
}
