/// 响应速度追踪器 — Codex-inspired response analytics。
///
/// 纯值类型，追踪 LLM 响应的关键时间点，计算：
/// - 思考时间（TTFT: Time To First Token）— 从用户提交到首个输出 token
/// - 生成速度（tokens/sec）— 流式输出的平均速率
///
/// 使用方式：
/// 1. Turn 开始时创建 `var tracker = ResponseSpeedTracker()`
/// 2. 收到首个 `.assistant` 消息时调用 `markFirstToken()`
/// 3. Turn 结束时调用 `computeSpeed(outputTokens:endTime:)` 获取结果
struct ResponseSpeedTracker: Sendable {

    /// Turn 开始时刻（用户提交时刻）。
    let turnStartTime: ContinuousClock.Instant

    /// 首个输出 token 到达时刻（首次 .assistant 消息）。
    private(set) var firstTokenTime: ContinuousClock.Instant?

    /// 是否已标记首个 token。
    var hasFirstToken: Bool { firstTokenTime != nil }

    init(turnStartTime: ContinuousClock.Instant = .now) {
        self.turnStartTime = turnStartTime
    }

    /// 标记首个输出 token 到达。
    ///
    /// 仅在第一次调用时生效，后续调用忽略。
    /// 应在收到第一个 `.assistant` 消息时调用。
    mutating func markFirstToken(now: ContinuousClock.Instant = .now) {
        guard firstTokenTime == nil else { return }
        firstTokenTime = now
    }

    /// 计算响应速度指标。
    ///
    /// - Parameters:
    ///   - outputTokens: 本 turn 的输出 token 数量
    ///   - endTime: Turn 结束时刻
    /// - Returns: 响应速度结果，数据不足时返回 nil
    func computeSpeed(
        outputTokens: Int,
        endTime: ContinuousClock.Instant = .now
    ) -> ResponseSpeed? {
        guard let firstToken = firstTokenTime else { return nil }

        let thinkingDuration = firstToken - turnStartTime
        let streamingDuration = endTime - firstToken

        // 流式时长需 > 0 才有有意义的速度值
        let streamingMs = durationToMs(streamingDuration)
        let tokensPerSecond: Double?
        if streamingMs > 0 && outputTokens > 0 {
            let streamingSeconds = Double(streamingMs) / 1000.0
            tokensPerSecond = Double(outputTokens) / streamingSeconds
        } else {
            tokensPerSecond = nil
        }

        return ResponseSpeed(
            thinkingDuration: thinkingDuration,
            streamingDuration: streamingDuration,
            tokensPerSecond: tokensPerSecond
        )
    }
}

/// 响应速度计算结果。
///
/// 包含思考时间、流式时长和平均生成速度，
/// 可格式化为紧凑字符串用于 turn summary。
struct ResponseSpeed: Sendable, Equatable {
    /// 思考时间（从用户提交到首个输出 token）。
    let thinkingDuration: Duration

    /// 流式输出时长（从首个到最后一个 token）。
    let streamingDuration: Duration

    /// 平均生成速度（tokens/second），无输出或时长过短时为 nil。
    let tokensPerSecond: Double?

    /// 渲染为紧凑的速度摘要（TTY 模式）。
    ///
    /// 格式示例：
    /// - 含速度：`"think 0.8s · 86 tok/s"`
    /// - 仅思考：`"think 1.2s"`
    /// - 仅速度：`"86 tok/s"`
    /// - 无数据：`nil`
    func formatCompact() -> String? {
        var parts: [String] = []

        let thinkMs = durationToMs(thinkingDuration)
        if thinkMs > 0 {
            parts.append("think \(formatDurationMs(thinkMs))")
        }

        if let speed = tokensPerSecond {
            let rounded = speed.rounded()
            if rounded >= 100 {
                parts.append("\(Int(rounded)) tok/s")
            } else {
                parts.append(String(format: "%.0f tok/s", speed))
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// 渲染为非 TTY 纯文本格式。
    ///
    /// 格式：`"think 0.8s, 86 tok/s"`（逗号分隔，无颜色）
    func formatPlain() -> String? {
        var parts: [String] = []

        let thinkMs = durationToMs(thinkingDuration)
        if thinkMs > 0 {
            parts.append("think \(formatDurationMs(thinkMs))")
        }

        if let speed = tokensPerSecond {
            let rounded = speed.rounded()
            if rounded >= 100 {
                parts.append("\(Int(rounded)) tok/s")
            } else {
                parts.append(String(format: "%.0f tok/s", speed))
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ")
    }
}
