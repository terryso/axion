import Foundation

/// 用户输入（App 名 / bundle id / 路径）→ 候选 App 的匹配置信度。
///
/// **与 `StorageConfidence` 故意分开**：两者都是 high/medium/low，但语义不同。
/// - `AppMatchConfidence`：描述「用户输入是否精确锁定某个 App 候选」（发现阶段）。
/// - `StorageConfidence`：描述 support 数据证据指向目标 App 的强度（扫描阶段，见 `SupportDataItem.matchConfidence`）。
///
/// 分开两个 enum 避免语义混淆（Dev Notes「冲突/方差说明」）。
public enum AppMatchConfidence: String, Sendable, Equatable, Codable {
    case high
    case medium
    case low
}
