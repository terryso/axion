import Foundation

/// App 卸载计划（扫描阶段产出，只读）。字段对齐 Epic「卸载计划字段表」。
///
/// `app` 取最高置信度候选（多候选时为占位）；`candidates` 列全部候选。低置信度 support 项
/// 单列到 `hintOnlySupportDataItems`，不进入可执行集（AC #7）。`requiresTypedConfirmation`
/// 是计划级标志（高风险时为 true），typed 确认的实际强制由入口实现（39.4 统一）。
///
/// 字段风格对齐 `StorageManifest`：显式 snake_case `CodingKeys` + `decodeIfPresent` 回退。
public struct AppUninstallPlan: Codable, Equatable, Sendable {

    /// 主候选 App（最高置信度；多候选时为占位）。
    public var app: AppCandidate
    /// 全部候选（含主候选；多候选时长度 > 1）。
    public var candidates: [AppCandidate]
    /// 卸载模式。
    public var uninstallMode: AppUninstallMode
    /// 可执行 support 数据项（中/高置信度）。
    public var supportDataItems: [SupportDataItem]
    /// 仅提示展示的低置信度 support 项（不进可执行集）。
    public var hintOnlySupportDataItems: [SupportDataItem]
    /// 计划级数据丢失风险（聚合 support 项后）。
    public var dataLossRisk: DataLossRisk
    /// 是否需 typed 确认（高风险时为 true；强制由入口实现）。
    public var requiresTypedConfirmation: Bool
    /// 阻断原因（如 `ambiguous_match` / `system_protected` / `outside_applications_dirs`）。
    public var blockedReasons: [String]
    /// 外部卸载提示（read-only，best-effort）。
    public var externalUninstallHints: [ExternalUninstallHint]

    enum CodingKeys: String, CodingKey {
        case app
        case candidates
        case uninstallMode = "uninstall_mode"
        case supportDataItems = "support_data_items"
        case hintOnlySupportDataItems = "hint_only_support_data_items"
        case dataLossRisk = "data_loss_risk"
        case requiresTypedConfirmation = "requires_typed_confirmation"
        case blockedReasons = "blocked_reasons"
        case externalUninstallHints = "external_uninstall_hints"
    }

    public init(
        app: AppCandidate,
        candidates: [AppCandidate],
        uninstallMode: AppUninstallMode,
        supportDataItems: [SupportDataItem],
        hintOnlySupportDataItems: [SupportDataItem],
        dataLossRisk: DataLossRisk,
        requiresTypedConfirmation: Bool,
        blockedReasons: [String],
        externalUninstallHints: [ExternalUninstallHint]
    ) {
        self.app = app
        self.candidates = candidates
        self.uninstallMode = uninstallMode
        self.supportDataItems = supportDataItems
        self.hintOnlySupportDataItems = hintOnlySupportDataItems
        self.dataLossRisk = dataLossRisk
        self.requiresTypedConfirmation = requiresTypedConfirmation
        self.blockedReasons = blockedReasons
        self.externalUninstallHints = externalUninstallHints
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(AppCandidate.self, forKey: .app)
            ?? AppCandidate(displayName: "", bundleIdentifier: "", bundlePath: "", version: "", sizeBytes: 0, isRunning: false, isSystemProtected: false, matchConfidence: .low)
        candidates = try c.decodeIfPresent([AppCandidate].self, forKey: .candidates) ?? []
        uninstallMode = try c.decodeIfPresent(AppUninstallMode.self, forKey: .uninstallMode) ?? .uninstallWithSupportReview
        supportDataItems = try c.decodeIfPresent([SupportDataItem].self, forKey: .supportDataItems) ?? []
        hintOnlySupportDataItems = try c.decodeIfPresent([SupportDataItem].self, forKey: .hintOnlySupportDataItems) ?? []
        dataLossRisk = try c.decodeIfPresent(DataLossRisk.self, forKey: .dataLossRisk) ?? .none
        requiresTypedConfirmation = try c.decodeIfPresent(Bool.self, forKey: .requiresTypedConfirmation) ?? false
        blockedReasons = try c.decodeIfPresent([String].self, forKey: .blockedReasons) ?? []
        externalUninstallHints = try c.decodeIfPresent([ExternalUninstallHint].self, forKey: .externalUninstallHints) ?? []
    }
}
