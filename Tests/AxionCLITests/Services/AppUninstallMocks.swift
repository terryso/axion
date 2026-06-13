import Foundation

@testable import AxionCLI
import AxionCore

/// App 卸载链路共享 Mock（Task 4.3 / Task 7 复用）。固定返回值注入，无外部依赖。
/// `@unchecked Sendable`：闭包/数组在测试构造后不可变，跨 actor 传递安全。

final class MockAppDiscoverer: AppDiscovering, @unchecked Sendable {
    private let candidates: [AppCandidate]
    init(candidates: [AppCandidate]) { self.candidates = candidates }
    func discover(query: String, searchRoots: [URL]) async throws -> [AppCandidate] { candidates }
}

final class MockSupportDataScanner: SupportDataScanning, @unchecked Sendable {
    private let items: [SupportDataItem]
    init(items: [SupportDataItem]) { self.items = items }
    func scan(for app: AppCandidate, homeDirectory: String) async -> [SupportDataItem] { items }
}

final class MockExternalHintReader: ExternalHintReading, @unchecked Sendable {
    private let hints: [ExternalUninstallHint]
    init(hints: [ExternalUninstallHint]) { self.hints = hints }
    func read(for app: AppCandidate) -> [ExternalUninstallHint] { hints }
}

/// 测试辅助：构造 `SupportDataItem`（精简默认值）。
func makeSupportItem(
    category: SupportDataCategory = .cache,
    path: String = "/tmp/x",
    matchConfidence: StorageConfidence = .high,
    dataRisk: DataRisk = .low,
    defaultSelected: Bool = true,
    requiresExplicitApproval: Bool = false
) -> SupportDataItem {
    SupportDataItem(
        category: category,
        path: path,
        sizeBytes: 0,
        matchEvidence: StorageEvidence(rule: "test", source: "test", confidence: matchConfidence),
        matchConfidence: matchConfidence,
        dataRisk: dataRisk,
        defaultSelected: defaultSelected,
        requiresExplicitApproval: requiresExplicitApproval
    )
}

/// 测试辅助：构造 `AppCandidate`（精简默认值）。
func makeCandidate(
    bundleId: String = "com.example.foo",
    displayName: String = "Foo",
    bundlePath: String = "/Applications/Foo.app",
    isSystemProtected: Bool = false,
    isRunning: Bool = false,
    matchConfidence: AppMatchConfidence = .high
) -> AppCandidate {
    AppCandidate(
        displayName: displayName,
        bundleIdentifier: bundleId,
        bundlePath: bundlePath,
        version: "1.0",
        teamIdentifier: "ADE12345",
        sizeBytes: 0,
        isRunning: isRunning,
        isSystemProtected: isSystemProtected,
        matchConfidence: matchConfidence
    )
}
