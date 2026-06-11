import Foundation
import AppKit

import AxionCore

/// App 发现实现（`import AppKit`，AxionCLI 直接用 AppKit 是既有惯例，参考 `SeatActivityMonitor`）。
///
/// **只读**：枚举 `searchRoots` 顶层 `*.app`（浅层，不进嵌套 bundle），读 bundle 元数据，
/// 计算 `isRunning` / `isSystemProtected` / `sizeBytes` / `matchConfidence`。无副作用。
///
/// 参考 `AxionHelper/Services/AppLauncher.swift` 的 Bundle 读取手法（L168-172）与 running
/// 检测手法（L97-106），但**仅参考手法，不 import AxionHelper**（Dev Notes「模块边界」）。
///
/// 纯函数 `classifyMatch` / `isSystemProtected` 独立可测，不依赖 NSWorkspace。
final class AppDiscoveryService: AppDiscovering, Sendable {

    init() {}

    func discover(query: String, searchRoots: [URL]) async -> [AppCandidate] {
        let fm = FileManager.default
        var candidates: [AppCandidate] = []

        for root in searchRoots {
            let rootPath = root.path
            guard let names = try? fm.contentsOfDirectory(atPath: rootPath) else { continue }
            for name in names where name.hasSuffix(".app") {
                let appURL = root.appendingPathComponent(name)
                guard let bundle = Bundle(url: appURL) else { continue }
                guard let bundleId = bundle.bundleIdentifier, !bundleId.isEmpty else { continue }

                let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? name.replacingOccurrences(of: ".app", with: "")
                let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
                    ?? ""

                let confidence = Self.classifyMatch(query: query, bundleIdentifier: bundleId, displayName: displayName)
                // 仅返回有匹配信号的候选（low 置信度无信号，不入候选集）。
                guard confidence != .low else { continue }

                candidates.append(AppCandidate(
                    displayName: displayName,
                    bundleIdentifier: bundleId,
                    bundlePath: appURL.path,
                    version: version,
                    teamIdentifier: Self.teamIdentifier(from: bundle),
                    sizeBytes: Self.readSize(path: appURL.path),
                    isRunning: Self.isRunning(bundleIdentifier: bundleId),
                    isSystemProtected: Self.isSystemProtected(bundlePath: appURL.path, bundleIdentifier: bundleId),
                    matchConfidence: confidence
                ))
            }
        }

        // 按置信度降序（high → medium），稳序便于上游取最高置信度候选。
        let order: [AppMatchConfidence] = [.high, .medium, .low]
        return candidates.sorted { lhs, rhs in
            let lo = order.firstIndex(of: lhs.matchConfidence) ?? order.count
            let ro = order.firstIndex(of: rhs.matchConfidence) ?? order.count
            return lo < ro
        }
    }

    // MARK: - Pure helpers (unit-testable, no AppKit state)

    /// 用户输入 → 候选 App 匹配置信度（纯函数）。
    ///
    /// - 精确 bundle id 相等（区分大小写，bundle id 本身大小写敏感）= **high**
    /// - displayName 精确相等（忽略大小写，含 `.app` 后缀归一）= **high**
    /// - bundle id 前缀匹配 / displayName 包含关系 = **medium**
    /// - 仅名称相似 / 模糊 = **low**
    static func classifyMatch(query: String, bundleIdentifier: String, displayName: String) -> AppMatchConfidence {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return .low }

        // 1. 精确 bundle id
        if !bundleIdentifier.isEmpty, q == bundleIdentifier { return .high }

        // 归一：剥 `.app` 后缀用于 displayName 比较
        let qNoApp = q.hasSuffix(".app") ? String(q.dropLast(4)) : q

        // 2. 精确 displayName（忽略大小写）
        if !displayName.isEmpty, qNoApp.caseInsensitiveCompare(displayName) == .orderedSame { return .high }

        // 3. bundle id 前缀匹配（如 query "com.example" 匹配 "com.example.foo"）
        if !bundleIdentifier.isEmpty, bundleIdentifier.hasPrefix(q), q.contains(".") { return .medium }

        // 4. displayName 包含关系（双向）
        let ql = qNoApp.lowercased()
        let dn = displayName.lowercased()
        if !ql.isEmpty && !dn.isEmpty && (dn.contains(ql) || ql.contains(dn)) { return .medium }

        return .low
    }

    /// 是否受系统保护（纯函数，基于 bundle id 与路径前缀，不访问文件系统）。
    ///
    /// - bundle id 命中 Apple 系统 bundle id 前缀（`com.apple.*`）→ true
    /// - 路径位于系统目录（`/System`、`/Library`、`/usr`、`/bin`、`/sbin`、`/private`）→ true
    /// - 其余（用户可读写 app 目录下的第三方 App）→ false
    ///
    /// 「路径不在 `/Applications` / `~/Applications` 之下」由上游 `AppUninstallPlanBuilder`
    /// 作为独立的 `outside_applications_dirs` 信号判定（AC #4 与 4.1.3 分开）。
    static func isSystemProtected(bundlePath: String, bundleIdentifier: String) -> Bool {
        if bundleIdentifier.hasPrefix("com.apple.") { return true }
        let systemDirs = ["/System", "/Library", "/usr", "/bin", "/sbin", "/private"]
        for d in systemDirs where bundlePath == d || bundlePath.hasPrefix(d + "/") {
            return true
        }
        return false
    }

    // MARK: - Bundle metadata (AppKit-backed)

    /// 是否正在运行（`isTerminated == false`，参考 AppLauncher L97-106 running 检测手法）。
    private static func isRunning(bundleIdentifier: String) -> Bool {
        let running = NSWorkspace.shared.runningApplications
        return running.contains { (app: NSRunningApplication) in
            app.bundleIdentifier == bundleIdentifier && !app.isTerminated
        }
    }

    /// team identifier 读取（best-effort）：读 Info.plist `ApplicationIdentifier` 前缀
    /// （格式 `<TEAMID>.<bundleId>`），失败置 nil，不阻塞发现。
    private static func teamIdentifier(from bundle: Bundle) -> String? {
        guard let appIdentifier = bundle.object(forInfoDictionaryKey: "ApplicationIdentifier") as? String,
              !appIdentifier.isEmpty else { return nil }
        let parts = appIdentifier.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        guard let team = parts.first, !team.isEmpty else { return nil }
        return String(team)
    }

    /// bundle 体积（与 `StorageExecutor.readSize` 同口径：目录走 `totalFileSize`）。
    private static func readSize(path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        guard let rv = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .totalFileSizeKey,
            .isDirectoryKey,
        ]) else { return 0 }
        let isDirectory = rv.isDirectory ?? false
        if isDirectory {
            return Int64(rv.totalFileSize ?? rv.fileSize ?? 0)
        }
        return Int64(rv.fileSize ?? 0)
    }
}
