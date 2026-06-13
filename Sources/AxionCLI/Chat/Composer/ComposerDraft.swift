
/// 编辑状态快照 — 保存 ChatComposer 的完整编辑状态。
///
/// 在模式切换（如进入 slashPopup / fileSearch）前调用 `snapshot()` 保存，
/// 取消时通过 `restore()` 恢复。初始实现仅保存 text（后续 Story 扩展 cursor/selection 等）。
struct ComposerDraft: Equatable {
    /// 当前输入文本
    var text: String
    /// 光标位置（字符偏移量）
    var cursor: Int

    /// 从当前编辑状态创建快照
    static func snapshot(text: String, cursor: Int) -> ComposerDraft {
        ComposerDraft(text: text, cursor: cursor)
    }

    /// 从 draft 恢复编辑状态
    func restore() -> (text: String, cursor: Int) {
        (text: text, cursor: cursor)
    }
}
