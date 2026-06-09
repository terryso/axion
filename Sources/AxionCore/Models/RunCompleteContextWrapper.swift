
public struct RunCompleteContextWrapper: Codable, Equatable, Sendable {
    public let task: String
    public let status: String
    public let totalCostUsd: Double
    public let durationMs: Int
    public let numTurns: Int
    public let inputTokens: Int
    public let outputTokens: Int

    public init(
        task: String,
        status: String,
        totalCostUsd: Double,
        durationMs: Int,
        numTurns: Int,
        inputTokens: Int,
        outputTokens: Int
    ) {
        self.task = task
        self.status = status
        self.totalCostUsd = totalCostUsd
        self.durationMs = durationMs
        self.numTurns = numTurns
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}
