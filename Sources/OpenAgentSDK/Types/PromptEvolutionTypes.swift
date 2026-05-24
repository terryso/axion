import Foundation

// MARK: - PromptEvolutionStrategy

/// Strategies for evolving an agent's system prompt.
///
/// Each strategy targets a distinct optimization goal:
/// - `refine`: Improve clarity and effectiveness of existing instructions.
/// - `expand`: Add new instructions based on observed gaps.
/// - `compress`: Reduce verbosity while preserving intent.
/// - `safety`: Add or strengthen safety guardrails.
public enum PromptEvolutionStrategy: String, Codable, Sendable, Equatable, CaseIterable {
    case refine
    case expand
    case compress
    case safety
}

// MARK: - PromptEvolutionConfig

/// Configuration for prompt evolution behavior.
public struct PromptEvolutionConfig: Sendable, Codable, Equatable {

    /// Strategies to apply during evolution. Defaults to all cases.
    public let strategies: [PromptEvolutionStrategy]

    /// Model identifier for the evolution LLM call.
    public let evolutionModel: String

    /// Maximum tokens for the evolution response.
    public let maxTokens: Int

    /// Sampling temperature for the evolution LLM call.
    public let temperature: Double

    /// Minimum number of messages required before evolution triggers.
    public let minConversationLength: Int

    /// Maximum number of changes to accept from a single evolution.
    public let maxChangesPerEvolution: Int

    public init(
        strategies: [PromptEvolutionStrategy] = PromptEvolutionStrategy.allCases,
        evolutionModel: String = "claude-haiku-4-5-20251001",
        maxTokens: Int = 2048,
        temperature: Double = 0.3,
        minConversationLength: Int = 6,
        maxChangesPerEvolution: Int = 5
    ) {
        precondition(!strategies.isEmpty, "PromptEvolutionConfig.strategies must be non-empty")
        precondition(!evolutionModel.isEmpty, "PromptEvolutionConfig.evolutionModel must be non-empty")
        precondition(maxTokens > 0, "PromptEvolutionConfig.maxTokens must be > 0")
        precondition(temperature >= 0 && temperature <= 1, "PromptEvolutionConfig.temperature must be in 0...1")
        precondition(minConversationLength >= 2, "PromptEvolutionConfig.minConversationLength must be >= 2")
        precondition(maxChangesPerEvolution > 0, "PromptEvolutionConfig.maxChangesPerEvolution must be > 0")

        self.strategies = strategies
        self.evolutionModel = evolutionModel
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.minConversationLength = minConversationLength
        self.maxChangesPerEvolution = maxChangesPerEvolution
    }
}

// MARK: - PromptChange

/// A single atomic change to the system prompt produced by evolution.
public struct PromptChange: Sendable, Codable, Equatable {

    /// The strategy that motivated this change.
    public let strategy: PromptEvolutionStrategy

    /// Which part of the prompt changed (e.g. "instructions", "guidelines", "safety").
    public let section: String

    /// The original text before evolution.
    public let original: String

    /// The evolved replacement text.
    public let modified: String

    /// Why this change was made.
    public let rationale: String

    public init(
        strategy: PromptEvolutionStrategy,
        section: String,
        original: String,
        modified: String,
        rationale: String
    ) {
        self.strategy = strategy
        self.section = section
        self.original = original
        self.modified = modified
        self.rationale = rationale
    }
}

// MARK: - PromptEvolutionResult

/// The outcome of a prompt evolution analysis.
public struct PromptEvolutionResult: Sendable, Equatable {

    /// Whether the LLM recommends changes.
    public let shouldEvolve: Bool

    /// The full evolved system prompt, or `nil` if no evolution is recommended.
    public let evolvedPrompt: String?

    /// Individual changes describing what was modified and why.
    public let changes: [PromptChange]

    /// The LLM's confidence in this evolution, clamped to 0...1.
    public let confidence: Double

    /// When this result was produced.
    public let evolvedAt: Date

    /// Factory for the no-evolution case.
    public static func noEvolution() -> PromptEvolutionResult {
        PromptEvolutionResult(
            shouldEvolve: false,
            evolvedPrompt: nil,
            changes: [],
            confidence: 0,
            evolvedAt: Date()
        )
    }

    public init(
        shouldEvolve: Bool,
        evolvedPrompt: String?,
        changes: [PromptChange],
        confidence: Double,
        evolvedAt: Date = Date()
    ) {
        self.shouldEvolve = shouldEvolve
        self.evolvedPrompt = evolvedPrompt
        self.changes = changes
        self.confidence = min(max(confidence, 0), 1)
        self.evolvedAt = evolvedAt
    }
}
