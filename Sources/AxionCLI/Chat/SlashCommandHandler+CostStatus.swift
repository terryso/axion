import OpenAgentSDK

extension SlashCommandHandler {

    // MARK: - Cost estimation constants

    /// Anthropic 公开定价（美元/百万 token），简化估算。
    private static let sonnetInputCostPerMTokens: Double = 3.0
    private static let sonnetOutputCostPerMTokens: Double = 15.0
    private static let sonnetCacheReadCostPerMTokens: Double = 0.30
    private static let opusInputCostPerMTokens: Double = 15.0
    private static let opusOutputCostPerMTokens: Double = 75.0
    private static let opusCacheReadCostPerMTokens: Double = 1.50

    // MARK: - /cost

    /// /cost — 显示累计 token 用量、上下文占用和预估成本。
    static func handleCost(usage: TokenUsage, model: String, contextTokens: Int = 0, contextWindow: Int = 0) -> String {
        let cost = estimateCost(usage: usage, model: model)
        let cacheCreation = usage.cacheCreationInputTokens ?? 0
        let cacheRead = usage.cacheReadInputTokens ?? 0
        let contextLine = ContextManager.formatContextUsage(
            usedTokens: contextTokens,
            contextWindow: contextWindow
        )
        return """
            Token 用量:
              Input:          \(usage.inputTokens)
              Output:         \(usage.outputTokens)
              Cache Creation: \(cacheCreation)
              Cache Read:     \(cacheRead)
              Total:          \(usage.totalTokens)
              \(contextLine)
            预估成本: \(cost)

            """
    }

    // MARK: - /status (AC5)

    /// 格式化当前会话状态卡。AC5。
    static func handleStatus(
        model: String,
        permissionMode: String,
        sessionId: String,
        contextTokens: Int,
        contextWindow: Int,
        cwd: String,
        usage: TokenUsage
    ) -> String {
        let shortId = String(sessionId.prefix(8))
        let contextLine = ContextManager.formatContextUsage(
            usedTokens: contextTokens,
            contextWindow: contextWindow
        )
        return """
        会话状态:
          模型:       \(model)
          权限:       \(permissionMode)
          Session:    \(shortId)
          \(contextLine)
          工作目录:   \(cwd)
          Token:      输入 \(usage.inputTokens) / 输出 \(usage.outputTokens) / 总 \(usage.totalTokens)

        """
    }

    // MARK: - Private

    private static func estimateCost(usage: TokenUsage, model: String) -> String {
        let inputCostPer1M: Double
        let outputCostPer1M: Double
        let cacheReadCostPer1M: Double
        if model.contains("opus") {
            inputCostPer1M = opusInputCostPerMTokens
            outputCostPer1M = opusOutputCostPerMTokens
            cacheReadCostPer1M = opusCacheReadCostPerMTokens
        } else {
            inputCostPer1M = sonnetInputCostPerMTokens
            outputCostPer1M = sonnetOutputCostPerMTokens
            cacheReadCostPer1M = sonnetCacheReadCostPerMTokens
        }
        let cacheRead = Double(usage.cacheReadInputTokens ?? 0)
        let cost = Double(usage.inputTokens) / 1_000_000 * inputCostPer1M
            + Double(usage.outputTokens) / 1_000_000 * outputCostPer1M
            + cacheRead / 1_000_000 * cacheReadCostPer1M
        return String(format: "$%.4f", cost)
    }
}
