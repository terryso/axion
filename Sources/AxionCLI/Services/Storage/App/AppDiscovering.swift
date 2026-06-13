import Foundation

import AxionCore

/// App 发现抽象（Protocol，测试注入 `MockAppDiscoverer` 用）。
///
/// 仅做**只读**枚举与元数据读取：扫描 `searchRoots`（默认 `/Applications` + `~/Applications`）
/// 下的顶层 `*.app`，读取 bundle 元数据，计算匹配置信度。不产生任何副作用。
///
/// `query` = 用户输入的 App 名 / bundle id / 路径。返回与 `query` 有匹配信号（非 low 置信度
/// 或精确路径/bundle id 命中）的候选，按置信度降序排列。多候选由上游 `AppUninstallPlanBuilder`
/// 决定是否收敛为唯一目标（AC #2）。
protocol AppDiscovering: Sendable {
    func discover(query: String, searchRoots: [URL]) async throws -> [AppCandidate]
}
