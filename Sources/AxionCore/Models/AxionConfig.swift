public enum LLMProvider: String, Sendable, Equatable, Codable {
    case anthropic
    case openai
}

/// 交互模式 prompt 显示配置。
///
/// 控制提示符中各信息段（进度条、回合数、费用、Git 分支）的显示开关，
/// 以及分支名的最大显示长度。所有字段为可选 — `nil` 表示显示（默认全开）。
///
/// ```json
/// {
///   "promptDisplay": {
///     "progressBar": false,
///     "cost": false,
///     "gitBranch": false,
///     "maxBranchLength": 12
///   }
/// }
/// ```
public struct PromptDisplayConfig: Equatable, Sendable {
    /// 是否显示上下文进度条。`nil` = 显示（默认）。
    public var progressBar: Bool?
    /// 是否显示回合号（T1, T2, …）。`nil` = 显示（默认）。
    public var turnCount: Bool?
    /// 是否显示累计会话费用。`nil` = 显示（默认）。
    public var cost: Bool?
    /// 是否显示 Git 分支名。`nil` = 显示（默认）。
    public var gitBranch: Bool?
    /// Git 分支名最大显示字符数。`nil` = 15（默认）。超出部分截断并加 `…` 前缀。
    public var maxBranchLength: Int?

    /// 进度条是否显示（nil → true）。
    public var showProgress: Bool { progressBar ?? true }
    /// 回合号是否显示（nil → true）。
    public var showTurn: Bool { turnCount ?? true }
    /// 费用是否显示（nil → true）。
    public var showCost: Bool { cost ?? true }
    /// Git 分支是否显示（nil → true）。
    public var showBranch: Bool { gitBranch ?? true }
    /// 分支名最大显示长度（nil → 15）。
    public var branchMaxLength: Int { maxBranchLength ?? 15 }

    public init(
        progressBar: Bool? = nil,
        turnCount: Bool? = nil,
        cost: Bool? = nil,
        gitBranch: Bool? = nil,
        maxBranchLength: Int? = nil
    ) {
        self.progressBar = progressBar
        self.turnCount = turnCount
        self.cost = cost
        self.gitBranch = gitBranch
        self.maxBranchLength = maxBranchLength
    }
}

extension PromptDisplayConfig: Codable {
    public enum CodingKeys: String, CodingKey {
        case progressBar, turnCount, cost, gitBranch, maxBranchLength
    }
}

public struct AxionConfig: Equatable, Sendable {

    public static let defaultReviewModel = "claude-haiku-4-5-20251001"
    public var apiKey: String?
    public var provider: LLMProvider
    public var baseURL: String?
    public var model: String
    public var maxSteps: Int
    public var maxBatches: Int
    public var maxReplanRetries: Int
    public var traceEnabled: Bool
    public var sharedSeatMode: Bool
    public var maxModelCalls: Int?
    public var maxScreenshots: Int?
    public var reviewMemoryInterval: Int?
    public var reviewSkillInterval: Int?
    public var reviewMinMessages: Int?
    public var reviewModel: String?
    public var curatorEnabled: Bool?
    public var curatorDryRun: Bool?
    public var curatorIntervalHours: Double?
    public var curatorStaleAfterDays: Int?
    public var curatorArchiveAfterDays: Int?
    public var gatewayEnabled: Bool?
    public var gatewayCuratorIdleHours: Double?
    public var gatewayCuratorIntervalHours: Double?
    public var gatewayTaskTimeoutMinutes: Double?
    public var gatewayNotifyCuratorResults: Bool?
    public var gatewayMemoryNudgeInterval: Int?
    public var telegramBotToken: String?
    public var telegramChatId: String?
    public var telegramAllowedUsers: String?
    public var telegramTypingEnabled: Bool?
    public var telegramTypingInterval: Double?
    public var env: [String: String]?
    public var promptDisplay: PromptDisplayConfig?

    public static let `default` = AxionConfig(
        apiKey: nil,
        provider: .anthropic,
        baseURL: nil,
        model: "claude-sonnet-4-20250514",
        maxSteps: 20,
        maxBatches: 6,
        maxReplanRetries: 3,
        traceEnabled: true,
        sharedSeatMode: false,
        maxModelCalls: nil,
        maxScreenshots: nil,
        reviewMemoryInterval: nil,
        reviewSkillInterval: nil,
        reviewMinMessages: nil,
        reviewModel: nil,
        curatorEnabled: nil,
        curatorDryRun: nil,
        curatorIntervalHours: nil,
        curatorStaleAfterDays: nil,
        curatorArchiveAfterDays: nil,
        gatewayEnabled: nil,
        gatewayCuratorIdleHours: nil,
        gatewayCuratorIntervalHours: nil,
        gatewayTaskTimeoutMinutes: nil,
        gatewayNotifyCuratorResults: nil,
        gatewayMemoryNudgeInterval: nil,
        telegramBotToken: nil,
        telegramChatId: nil,
        telegramAllowedUsers: nil,
        telegramTypingEnabled: nil,
        telegramTypingInterval: nil,
        env: nil,
        promptDisplay: nil
    )

    public init(
        apiKey: String?,
        provider: LLMProvider = .anthropic,
        baseURL: String? = nil,
        model: String = "claude-sonnet-4-20250514",
        maxSteps: Int = 20,
        maxBatches: Int = 6,
        maxReplanRetries: Int = 3,
        traceEnabled: Bool = true,
        sharedSeatMode: Bool = false,
        maxModelCalls: Int? = nil,
        maxScreenshots: Int? = nil,
        reviewMemoryInterval: Int? = nil,
        reviewSkillInterval: Int? = nil,
        reviewMinMessages: Int? = nil,
        reviewModel: String? = nil,
        curatorEnabled: Bool? = nil,
        curatorDryRun: Bool? = nil,
        curatorIntervalHours: Double? = nil,
        curatorStaleAfterDays: Int? = nil,
        curatorArchiveAfterDays: Int? = nil,
        gatewayEnabled: Bool? = nil,
        gatewayCuratorIdleHours: Double? = nil,
        gatewayCuratorIntervalHours: Double? = nil,
        gatewayTaskTimeoutMinutes: Double? = nil,
        gatewayNotifyCuratorResults: Bool? = nil,
        gatewayMemoryNudgeInterval: Int? = nil,
        telegramBotToken: String? = nil,
        telegramChatId: String? = nil,
        telegramAllowedUsers: String? = nil,
        telegramTypingEnabled: Bool? = nil,
        telegramTypingInterval: Double? = nil,
        env: [String: String]? = nil,
        promptDisplay: PromptDisplayConfig? = nil
    ) {
        self.apiKey = apiKey
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.maxSteps = maxSteps
        self.maxBatches = maxBatches
        self.maxReplanRetries = maxReplanRetries
        self.traceEnabled = traceEnabled
        self.sharedSeatMode = sharedSeatMode
        self.maxModelCalls = maxModelCalls
        self.maxScreenshots = maxScreenshots
        self.reviewMemoryInterval = reviewMemoryInterval
        self.reviewSkillInterval = reviewSkillInterval
        self.reviewMinMessages = reviewMinMessages
        self.reviewModel = reviewModel
        self.curatorEnabled = curatorEnabled
        self.curatorDryRun = curatorDryRun
        self.curatorIntervalHours = curatorIntervalHours
        self.curatorStaleAfterDays = curatorStaleAfterDays
        self.curatorArchiveAfterDays = curatorArchiveAfterDays
        self.gatewayEnabled = gatewayEnabled
        self.gatewayCuratorIdleHours = gatewayCuratorIdleHours
        self.gatewayCuratorIntervalHours = gatewayCuratorIntervalHours
        self.gatewayTaskTimeoutMinutes = gatewayTaskTimeoutMinutes
        self.gatewayNotifyCuratorResults = gatewayNotifyCuratorResults
        self.gatewayMemoryNudgeInterval = gatewayMemoryNudgeInterval
        self.telegramBotToken = telegramBotToken
        self.telegramChatId = telegramChatId
        self.telegramAllowedUsers = telegramAllowedUsers
        self.telegramTypingEnabled = telegramTypingEnabled
        self.telegramTypingInterval = telegramTypingInterval
        self.env = env
        self.promptDisplay = promptDisplay
    }

    public var tgTypingEnabled: Bool { telegramTypingEnabled ?? true }
    public var tgTypingInterval: Double { telegramTypingInterval ?? 4.0 }
    public var memoryNudgeInterval: Int { gatewayMemoryNudgeInterval ?? 4 }
}

extension AxionConfig: Codable {
    public enum CodingKeys: String, CodingKey {
        case apiKey, provider, baseURL, model, maxSteps, maxBatches, maxReplanRetries, traceEnabled, sharedSeatMode, maxModelCalls, maxScreenshots
        case reviewMemoryInterval, reviewSkillInterval, reviewMinMessages, reviewModel
        case curatorEnabled, curatorDryRun, curatorIntervalHours, curatorStaleAfterDays, curatorArchiveAfterDays
        case gatewayEnabled, gatewayCuratorIdleHours, gatewayCuratorIntervalHours, gatewayTaskTimeoutMinutes, gatewayNotifyCuratorResults, gatewayMemoryNudgeInterval
        case telegramBotToken, telegramChatId, telegramAllowedUsers, telegramTypingEnabled, telegramTypingInterval
        case env, promptDisplay
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        provider = try c.decodeIfPresent(LLMProvider.self, forKey: .provider) ?? Self.default.provider
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? Self.default.model
        maxSteps = try c.decodeIfPresent(Int.self, forKey: .maxSteps) ?? Self.default.maxSteps
        maxBatches = try c.decodeIfPresent(Int.self, forKey: .maxBatches) ?? Self.default.maxBatches
        maxReplanRetries = try c.decodeIfPresent(Int.self, forKey: .maxReplanRetries) ?? Self.default.maxReplanRetries
        traceEnabled = try c.decodeIfPresent(Bool.self, forKey: .traceEnabled) ?? Self.default.traceEnabled
        sharedSeatMode = try c.decodeIfPresent(Bool.self, forKey: .sharedSeatMode) ?? Self.default.sharedSeatMode
        maxModelCalls = try c.decodeIfPresent(Int.self, forKey: .maxModelCalls) ?? Self.default.maxModelCalls
        maxScreenshots = try c.decodeIfPresent(Int.self, forKey: .maxScreenshots) ?? Self.default.maxScreenshots
        reviewMemoryInterval = try c.decodeIfPresent(Int.self, forKey: .reviewMemoryInterval)
        reviewSkillInterval = try c.decodeIfPresent(Int.self, forKey: .reviewSkillInterval)
        reviewMinMessages = try c.decodeIfPresent(Int.self, forKey: .reviewMinMessages)
        reviewModel = try c.decodeIfPresent(String.self, forKey: .reviewModel)
        curatorEnabled = try c.decodeIfPresent(Bool.self, forKey: .curatorEnabled)
        curatorDryRun = try c.decodeIfPresent(Bool.self, forKey: .curatorDryRun)
        curatorIntervalHours = try c.decodeIfPresent(Double.self, forKey: .curatorIntervalHours)
        curatorStaleAfterDays = try c.decodeIfPresent(Int.self, forKey: .curatorStaleAfterDays)
        curatorArchiveAfterDays = try c.decodeIfPresent(Int.self, forKey: .curatorArchiveAfterDays)
        gatewayEnabled = try c.decodeIfPresent(Bool.self, forKey: .gatewayEnabled)
        gatewayCuratorIdleHours = try c.decodeIfPresent(Double.self, forKey: .gatewayCuratorIdleHours)
        gatewayCuratorIntervalHours = try c.decodeIfPresent(Double.self, forKey: .gatewayCuratorIntervalHours)
        gatewayTaskTimeoutMinutes = try c.decodeIfPresent(Double.self, forKey: .gatewayTaskTimeoutMinutes)
        gatewayNotifyCuratorResults = try c.decodeIfPresent(Bool.self, forKey: .gatewayNotifyCuratorResults)
        gatewayMemoryNudgeInterval = try c.decodeIfPresent(Int.self, forKey: .gatewayMemoryNudgeInterval)
        telegramBotToken = try c.decodeIfPresent(String.self, forKey: .telegramBotToken)
        telegramChatId = try c.decodeIfPresent(String.self, forKey: .telegramChatId)
        telegramAllowedUsers = try c.decodeIfPresent(String.self, forKey: .telegramAllowedUsers)
        telegramTypingEnabled = try c.decodeIfPresent(Bool.self, forKey: .telegramTypingEnabled)
        telegramTypingInterval = try c.decodeIfPresent(Double.self, forKey: .telegramTypingInterval)
        env = try c.decodeIfPresent([String: String].self, forKey: .env)
        promptDisplay = try c.decodeIfPresent(PromptDisplayConfig.self, forKey: .promptDisplay)
    }
}
