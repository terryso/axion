
/// Slash 命令上下文过滤 — AC3: 上下文感知过滤。
///
/// 纯 struct，零外部依赖。根据当前运行状态过滤可用命令：
/// - agent 忙碌时排除 `availableDuringTask == false` 的命令
/// - side 会话中排除 `availableInSide == false` 的命令
struct SlashCommandContext: Equatable, Sendable {

    /// agent 是否正在执行任务
    let isAgentBusy: Bool

    /// 是否在 side 会话中（功能延后到 38.8，预留字段）
    let isSideSession: Bool

    // MARK: - Filter

    /// 根据上下文过滤可用命令。
    /// - Parameter commands: 候选命令列表
    /// - Returns: 过滤后的命令列表
    func filter(_ commands: [SlashCommand]) -> [SlashCommand] {
        commands.filter { cmd in
            if isAgentBusy && !cmd.availableDuringTask {
                return false
            }
            if isSideSession && !cmd.availableInSide {
                return false
            }
            return true
        }
    }
}
