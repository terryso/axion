import Foundation

// MARK: - PromptEvolverEngine

/// Pure computation engine for prompt evolution.
///
/// Takes an `LLMClient` and produces evolution results based on conversation analysis.
/// Thread safety is handled by the caller (typically `PromptEvolverPlugin`, which is an actor).
public struct PromptEvolverEngine: Sendable {

    private let client: LLMClient

    public init(client: LLMClient) {
        self.client = client
    }

    /// Analyze a conversation and produce an evolved version of the system prompt.
    public func evolve(
        currentPrompt: String,
        messages: [SDKMessage],
        config: PromptEvolutionConfig
    ) async throws -> PromptEvolutionResult {
        // Step 1: Check minimum conversation length
        guard messages.count >= config.minConversationLength else {
            return PromptEvolutionResult.noEvolution()
        }

        // Step 2: Serialize conversation and build system prompt
        let serialized = serializeMessages(messages)
        let systemPrompt = buildSystemPrompt(
            currentPrompt: currentPrompt,
            strategies: config.strategies
        )
        let userMessage: [String: Any] = [
            "role": "user",
            "content": "Current system prompt:\n```\n\(currentPrompt)\n```\n\nConversation to analyze:\n\(serialized)"
        ]

        // Step 3: Call LLM
        let response: [String: Any]
        do {
            response = try await client.sendMessage(
                model: config.evolutionModel,
                messages: [userMessage],
                maxTokens: config.maxTokens,
                system: systemPrompt,
                tools: nil,
                toolChoice: nil,
                thinking: nil,
                temperature: config.temperature
            )
        } catch {
            return PromptEvolutionResult.noEvolution()
        }

        // Step 4: Parse response
        let responseText = extractTextFromResponse(response)
        let result = parseEvolutionResponse(responseText, config: config)

        return result
    }

    // MARK: - Private Helpers

    private func serializeMessages(_ messages: [SDKMessage]) -> String {
        messages.map { msg in
            switch msg {
            case .userMessage:
                return "[User]: \(msg.text)"
            case .assistant:
                return "[Assistant]: \(msg.text)"
            case .toolUse(let data):
                return "[Tool Use]: \(data.toolName)"
            case .toolResult(let data):
                let preview = String(data.content.prefix(200))
                return "[Tool Result]: \(preview)"
            default:
                return nil
            }
        }.compactMap { $0 }.joined(separator: "\n")
    }

    private func buildSystemPrompt(
        currentPrompt: String,
        strategies: [PromptEvolutionStrategy]
    ) -> String {
        let strategyList = strategies.map(\.rawValue).joined(separator: ", ")
        return """
        You are a prompt evolution analyst. Your task is to analyze an agent's system prompt \
        and its conversation history, then suggest improvements.

        Focus on these evolution strategies: \(strategyList)

        - refine: Improve clarity and effectiveness of existing instructions
        - expand: Add new instructions based on observed gaps in agent behavior
        - compress: Reduce verbosity while preserving intent (for long prompts)
        - safety: Add or strengthen safety guardrails based on observed risky patterns

        Return a JSON object with this exact structure:
        {
          "shouldEvolve": true/false,
          "evolvedPrompt": "The complete evolved system prompt (or omit if shouldEvolve is false)",
          "changes": [
            {
              "strategy": "refine|expand|compress|safety",
              "section": "which part changed (e.g. instructions, guidelines, safety)",
              "original": "the original text",
              "modified": "the evolved text",
              "rationale": "why this change improves the prompt"
            }
          ],
          "confidence": 0.85
        }

        Only recommend evolution if you have concrete evidence from the conversation that the \
        current prompt is suboptimal. If the prompt is working well, return shouldEvolve: false.
        """
    }

    private func extractTextFromResponse(_ response: [String: Any]) -> String {
        guard let content = response["content"] as? [[String: Any]] else {
            return ""
        }
        for block in content {
            if block["type"] as? String == "text",
               let text = block["text"] as? String {
                return text
            }
        }
        return ""
    }

    private func stripCodeFences(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            if let newlineRange = trimmed.range(of: "\n", options: [], range: trimmed.startIndex..<trimmed.endIndex) {
                trimmed = String(trimmed[newlineRange.upperBound...])
            } else {
                trimmed = String(trimmed.dropFirst(3))
            }
        }

        if trimmed.hasSuffix("```") {
            trimmed = String(trimmed[..<trimmed.index(trimmed.endIndex, offsetBy: -3)])
        }

        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseEvolutionResponse(
        _ text: String,
        config: PromptEvolutionConfig
    ) -> PromptEvolutionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PromptEvolutionResult.noEvolution()
        }

        let jsonText = stripCodeFences(trimmed)

        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return PromptEvolutionResult.noEvolution()
        }

        let shouldEvolve = json["shouldEvolve"] as? Bool ?? false

        guard shouldEvolve else {
            return PromptEvolutionResult.noEvolution()
        }

        let evolvedPrompt = json["evolvedPrompt"] as? String
        let confidence = json["confidence"] as? Double ?? 0.5

        var changes: [PromptChange] = []
        if let changesArray = json["changes"] as? [[String: Any]] {
            for changeDict in changesArray {
                guard let strategyStr = changeDict["strategy"] as? String,
                      let strategy = PromptEvolutionStrategy(rawValue: strategyStr),
                      let section = changeDict["section"] as? String,
                      let original = changeDict["original"] as? String,
                      let modified = changeDict["modified"] as? String,
                      let rationale = changeDict["rationale"] as? String
                else { continue }

                changes.append(PromptChange(
                    strategy: strategy,
                    section: section,
                    original: original,
                    modified: modified,
                    rationale: rationale
                ))
            }
        }

        // Cap changes to maxChangesPerEvolution
        if changes.count > config.maxChangesPerEvolution {
            changes = Array(changes.prefix(config.maxChangesPerEvolution))
        }

        return PromptEvolutionResult(
            shouldEvolve: true,
            evolvedPrompt: evolvedPrompt,
            changes: changes,
            confidence: confidence
        )
    }
}
