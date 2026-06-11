import Foundation

/// 计划级数据丢失风险（聚合 support 数据项 `DataRisk` 后的总结信号，用于决定是否需 typed 确认）。
///
/// 与 `DataRisk` 区别：不含 `forbidden`（forbidden 项 MVP 不处理，不进入计划级聚合的高位）。
/// `none` 表示无可执行 support 项。提供 `max` 聚合（思路复用 `RiskLevel.max`）。
public enum DataLossRisk: String, Sendable, Equatable, Codable {
    case none
    case low
    case medium
    case high

    /// 取两者中更高的一级（用于计划级风险聚合）。
    public static func max(_ a: DataLossRisk, _ b: DataLossRisk) -> DataLossRisk {
        let order: [DataLossRisk] = [.none, .low, .medium, .high]
        return order.firstIndex(of: a)! >= order.firstIndex(of: b)! ? a : b
    }
}
