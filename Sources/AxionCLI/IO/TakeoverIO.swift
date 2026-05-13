import Foundation

/// 用户在 takeover 暂停期间可选择的行为。
enum TakeoverAction: String, Equatable {
    case resume
    case skip
    case abort

    /// 从 stdin 输入解析用户意图。
    ///
    /// - `nil` / 空 / `"continue"` / 回车 → `.resume`
    /// - `"skip"` → `.skip`
    /// - `"abort"` / `"quit"` → `.abort`
    static func fromInput(_ input: String?) -> TakeoverAction {
        guard let input else { return .resume }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if trimmed.isEmpty || trimmed == "continue" { return .resume }
        if trimmed == "skip" { return .skip }
        if trimmed == "abort" || trimmed == "quit" { return .abort }
        return .resume
    }
}

/// Takeover 期间的终端 I/O，通过注入的 write/readLine 实现可测试。
final class TakeoverIO {
    let write: (String) -> Void
    let readLine: () -> String?

    init(
        write: @escaping (String) -> Void = { fputs($0 + "\n", stdout); fflush(stdout) },
        readLine: @escaping () -> String? = { Swift.readLine() }
    ) {
        self.write = write
        self.readLine = readLine
    }

    /// 显示接管提示并等待用户输入，返回对应行为。
    /// - Parameter completedSteps: 已完成的步骤数，用于 abort 时显示摘要。
    func displayTakeoverPrompt(reason: String, allowForeground: Bool, completedSteps: Int = 0) -> TakeoverAction {
        write("")
        write("━━━ Axion Takeover ━━━")
        write("任务受阻: \(reason)")
        if allowForeground {
            write("前台操作限制已暂时解除，你可以自由操作桌面。")
        }
        write("")
        write("操作: [Enter] 继续执行 | skip 跳过此步骤 | abort 终止任务")

        let input = readLine()
        let action = TakeoverAction.fromInput(input)

        switch action {
        case .resume:
            write("[axion] 用户继续执行...")
        case .skip:
            write("[axion] 跳过当前步骤...")
        case .abort:
            write("[axion] 用户终止任务。已完成 \(completedSteps) 步。")
        }

        return action
    }

    /// 显示超时提示。
    func displayTimeoutPrompt() {
        write("")
        write("[axion] 接管超时（5 分钟无操作），任务终止。")
    }
}
