import Foundation

/// 决定如何响应 SDK 的 `.system(.paused)` 事件。
///
/// 纯函数 seam（镜像 `ChatCommandInputRouter` 的抽取模式）：把 (canResume, 用户输入动作)
/// 映射为对 agent 的指令，便于单测且不直接依赖 `Agent` / stdin / `SignalHandler`。
///
/// 调用点（`ChatCommand`）负责把 `Decision` 翻译成具体调用：
/// - `.resume(context:)` → `agent.resume(context:)`
/// - `.interrupt` → `SignalHandler.simulateFire()` + `agent.interrupt()`
///
/// 不引入 `Agent` 的 Protocol 抽象，避免对 SDK `final class Agent` 做 retroactive conformance。
struct PausedEventDecider {

    /// 对 paused agent 应执行的动作。
    enum Decision: Equatable {
        /// 注入人类上下文并恢复执行（含 skip —— 以 "skip" 作为 context 恢复）。
        case resume(context: String)
        /// 终止任务（调用方需同时 simulateFire 以保持中断语义，避免 turn-end 误判为正常完成）。
        case interrupt
    }

    /// 根据暂停事件与用户输入决定恢复方式。
    ///
    /// - Parameters:
    ///   - canResume: SDK 报告的 `PausedData.canResume`。`false` 时强制终止（防御；正常 `.paused` 恒为 true）。
    ///   - action: `TakeoverIO` 解析出的用户动作。
    ///   - text: 用户的原始输入文本（可能为 nil / 空）。
    static func decide(
        canResume: Bool,
        action: TakeoverAction,
        text: String?
    ) -> Decision {
        // 边界 A：不可恢复 → 终止（防止 stream 永久挂起）
        if !canResume { return .interrupt }

        switch action {
        case .resume:
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                return .resume(context: trimmed)
            }
            return .resume(context: "用户已确认继续")
        case .skip:
            return .resume(context: "skip")
        case .abort:
            return .interrupt
        }
    }
}
