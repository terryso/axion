import Foundation

/// Support 数据候选分类。对齐 Epic「support 数据分类表」与扫描路径模板。
///
/// `forbidden` 用于云同步 / Keychain / 浏览器扩展等 MVP 不处理的类别
/// （AC #8：`dataRisk = forbidden`，executor 拒绝执行）。
public enum SupportDataCategory: String, Sendable, Equatable, Codable {
    case cache
    case logs
    case httpStorage = "http_storage"
    case webKit = "web_kit"
    case preferences
    case savedState = "saved_state"
    case applicationScripts = "application_scripts"
    case applicationSupport = "application_support"
    case container
    case groupContainer = "group_container"
    case launchAgent = "launch_agent"
    case forbidden
}
