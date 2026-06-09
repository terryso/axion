
/// Composer 交互模式状态机。
///
/// 定义 ChatComposer 的当前交互模式：
/// - `normal`: 普通文本输入模式
/// - `slashPopup`: 斜杠命令补全弹出层（由 Story 38.2 实现 UI）
/// - `historySearch`: 历史搜索模式（由 Story 38.4 实现 UI）
/// - `fileSearch`: 文件搜索模式（由后续 Story 实现）
/// - `approval`: 审批确认模式
enum ComposerMode: Equatable {
    case normal
    case slashPopup(query: String)
    case historySearch(query: String)
    case fileSearch(query: String)
    case approval

    /// 是否为普通输入模式
    var isNormal: Bool {
        if case .normal = self { return true }
        return false
    }
}
