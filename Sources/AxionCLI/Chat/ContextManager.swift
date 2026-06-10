import Foundation
import OpenAgentSDK

/// 上下文管理核心逻辑。纯函数 struct，不持有状态。
///
/// 职责：
/// - 判断是否需要自动压缩（≥80% 上下文窗口）
/// - 格式化压缩结果消息
/// - 格式化上下文用量显示
struct ContextManager {

    /// 连续压缩失败上限，超过后停止自动尝试。
    static let maxConsecutiveFailures = 3

    // MARK: - Token Estimation

    /// 估算消息数组的 token 数，委托 SDK 的 `estimateMessagesTokens()`。
    ///
    /// - Parameter messages: SDK 消息数组（`[[String: Any]]` 兼容格式）
    /// - Returns: 估算 token 数
    static func estimateContextTokens(messages: [[String: Any]]) -> Int {
        // SDK 的 estimateMessagesTokens 接受 [SDKMessage]，不是 [[String: Any]]
        // 使用简单的 4 chars/token 启发式估算（与 SDK 一致）
        var totalChars = 0
        for msg in messages {
            if let content = msg["content"] {
                if let str = content as? String {
                    totalChars += str.count
                } else if let blocks = content as? [[String: Any]] {
                    for block in blocks {
                        if let text = block["text"] as? String {
                            totalChars += text.count
                        }
                    }
                }
            }
        }
        return totalChars / 4
    }

    /// 使用 SDK 消息估算上下文 token 数。
    ///
    /// 使用 4 chars/token 启发式估算（与 SDK `estimateMessagesTokens` 一致），
    /// 因为 SDK 的函数是 internal，不可从外部模块调用。
    ///
    /// - Parameter messages: SDKMessage 数组
    /// - Returns: 估算 token 数
    static func estimateContextTokens(messages: [SDKMessage]) -> Int {
        var totalChars = 0
        for msg in messages {
            switch msg {
            case .userMessage(let data):
                totalChars += data.message.count
            case .assistant(let data):
                totalChars += data.text.count
            case .toolUse(let data):
                totalChars += data.input.count
            case .toolResult(let data):
                totalChars += data.content.count
            default:
                break
            }
        }
        return max(totalChars / 4, 0)
    }

    // MARK: - Formatting

    /// 格式化自动压缩成功消息。
    ///
    /// - Parameters:
    ///   - beforeTokens: 压缩前 token 数
    ///   - afterTokens: 压缩后 token 数
    /// - Returns: 格式化消息，如 `[axion] 上下文已自动压缩 (45k → 8k tokens)`
    static func formatCompactMessage(beforeTokens: Int, afterTokens: Int) -> String {
        let before = BannerRenderer.formatTokenCount(beforeTokens)
        let after = BannerRenderer.formatTokenCount(afterTokens)
        return "[axion] 上下文已自动压缩 (\(before) → \(after) tokens)\n"
    }

    /// 格式化压缩失败消息。
    ///
    /// - Parameter failureCount: 连续失败次数
    /// - Returns: 警告消息
    static func formatCompactFailureMessage(failureCount: Int) -> String {
        if failureCount >= maxConsecutiveFailures {
            return "[axion] ⚠️ 上下文压缩连续失败 \(failureCount) 次，已停止自动压缩尝试\n"
        }
        return "[axion] ⚠️ 上下文压缩失败，继续使用当前上下文\n"
    }

    /// 格式化上下文用量行，用于 `/cost` 输出。
    ///
    /// - Parameters:
    ///   - usedTokens: 当前上下文占用 token 数
    ///   - contextWindow: 上下文窗口大小
    /// - Returns: 格式化行，如 `Context: 12k/200k (6%)`
    static func formatContextUsage(usedTokens: Int, contextWindow: Int) -> String {
        let used = BannerRenderer.formatTokenCount(usedTokens)
        let max = BannerRenderer.formatTokenCount(contextWindow)
        let pct = contextWindow > 0
            ? Int(Double(usedTokens) / Double(contextWindow) * 100)
            : 0
        return "Context:        \(used)/\(max) (\(pct)%)"
    }

    /// Axion 侧上下文警告阈值比例（80%）
    static let contextWarningRatio = 0.80

    /// 格式化 `/compact` 显示的当前上下文状态。
    ///
    /// 使用 80% 阈值判断是否显示自动压缩提示。
    static func formatCompactStatus(usedTokens: Int, contextWindow: Int) -> String {
        let used = BannerRenderer.formatTokenCount(usedTokens)
        let maxTokenStr = BannerRenderer.formatTokenCount(contextWindow)
        let pct = contextWindow > 0
            ? Int(Double(usedTokens) / Double(contextWindow) * 100)
            : 0

        let warningThreshold = contextWindow > 0
            ? Int(Double(contextWindow) * contextWarningRatio)
            : 0
        if contextWindow > 0 && usedTokens >= warningThreshold {
            return "[axion] 当前上下文: \(used)/\(maxTokenStr) (\(pct)%)，上下文接近上限，建议使用 /compact 压缩\n"
        }
        return "[axion] 当前上下文: \(used)/\(maxTokenStr) (\(pct)%)\n"
    }

    // MARK: - Turn-end Context Warning

    /// 回合结束时的上下文警告阈值（70%）。
    ///
    /// 低于 `contextWarningRatio`（80% 自动压缩阈值），在自动压缩触发前
    /// 给用户一个温和的提醒。Codex-inspired: `percent_of_context_window_remaining()`
    /// 在上下文不足时主动提醒用户。
    static let contextSuggestThreshold = 0.70

    /// 格式化回合结束时的上下文警告提示。
    ///
    /// 当上下文使用率 ≥70% 且 <80%（自动压缩触发前）时，显示黄色警告
    /// 并建议使用 `/compact`。≥80% 时自动压缩会处理，无需额外提示。
    ///
    /// - Parameters:
    ///   - usedTokens: 当前上下文 token 数
    ///   - contextWindow: 上下文窗口大小
    ///   - isTTY: 是否连接到 TTY
    ///   - profile: 终端颜色配置
    /// - Returns: 警告字符串，上下文不足时返回 `nil`
    static func formatTurnEndContextWarning(
        usedTokens: Int,
        contextWindow: Int,
        isTTY: Bool = isatty(STDERR_FILENO) != 0,
        profile: TerminalColorProfile = .detect()
    ) -> String? {
        guard contextWindow > 0 else { return nil }
        let pct = Double(usedTokens) / Double(contextWindow)
        let pctInt = Int(pct * 100)

        // 仅在 70%-80% 范围内提示（≥80% 由自动压缩处理）
        let suggestThreshold = Double(contextWindow) * contextSuggestThreshold
        let autoCompactThreshold = Double(contextWindow) * contextWarningRatio
        guard Double(usedTokens) >= suggestThreshold && Double(usedTokens) < autoCompactThreshold else {
            return nil
        }

        let yellow: String
        let dim: String

        switch profile {
        case .trueColor:
            yellow = "\u{1B}[38;2;255;193;7m"   // amber
            dim = "\u{1B}[38;2;148;163;184m"     // slate-400
        case .ansi256:
            yellow = "\u{1B}[38;5;178m"
            dim = "\u{1B}[38;5;145m"
        case .ansi16:
            yellow = "\u{1B}[33m"
            dim = "\u{1B}[37m"
        case .unknown:
            yellow = ""
            dim = ""
        }

        if isTTY {
            let r = "\u{1B}[0m"
            return "\(yellow)⚠ 上下文 \(pctInt)% — 建议使用 \(dim)/compact\(r)\(yellow) 压缩以避免自动截断\(r)\n"
        } else {
            return "[warning: context \(pctInt)% — consider /compact]\n"
        }
    }
}
