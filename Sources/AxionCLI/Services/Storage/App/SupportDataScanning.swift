import Foundation

import AxionCore

/// Support 数据扫描抽象（Protocol，测试注入 `MockSupportDataScanner` 用）。
///
/// **只读**：对单个 `AppCandidate` 探测常见 support 数据目录，产出候选 `SupportDataItem`。
/// 不移动 / 不删除 / 不创建目录，无副作用。
///
/// **安全由精确探测保障**（AC #13）：仅探测 bundle-id 键控的具体子路径
/// （如 `~/Library/Caches/<bundleId>`），**不**对 `~/Library` 做全量递归枚举，
/// **不**调用 `StorageExclusions.evaluate()`（该方法对整个 `~/Library` 恒定排除）。
/// 仅复用 `StorageExclusions.standardize(_:home:)` 做路径标准化。
protocol SupportDataScanning: Sendable {
    func scan(for app: AppCandidate, homeDirectory: String) async -> [SupportDataItem]
}
