import Foundation

/// Builds a JSON response string using JSONSerialization for safe encoding of user-provided values.
func reviewJSONResponse(_ fields: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: fields),
          let result = String(data: data, encoding: .utf8) else {
        return "{\"success\": false, \"error\": \"JSON encoding failed\"}"
    }
    return result
}

// MARK: - createReviewTools

/// Creates all four review tools for injection into a forked review agent.
///
/// This is the single entry point for `ReviewOrchestrator` (Story 24.3) to
/// create the tool set and pass it into the review Agent.
///
/// - Parameters:
///   - factStore: The fact store for saving memory facts.
///   - skillRegistry: The registry for skill lookups, registration, and replacement.
///   - skillEvolver: The evolver for applying skill updates.
/// - Returns: An array of four `ToolProtocol` instances.
public func createReviewTools(
    factStore: FactStore,
    skillRegistry: SkillRegistry,
    skillEvolver: any SkillEvolver
) -> [ToolProtocol] {
    [
        createReviewMemoryTool(factStore: factStore),
        createReviewSkillUpdateTool(skillRegistry: skillRegistry, skillEvolver: skillEvolver),
        createReviewSkillCreateTool(skillRegistry: skillRegistry),
        createReviewSkillFileTool(skillRegistry: skillRegistry),
    ]
}
