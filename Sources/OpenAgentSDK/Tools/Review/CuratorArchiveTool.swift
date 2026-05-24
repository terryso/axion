import Foundation

// MARK: - CuratorArchiveInput

private struct CuratorArchiveInput: Codable {
    let skillName: String
    let absorbedInto: String?
}

// MARK: - createCuratorArchiveTool

/// Creates the `curator_archive_skill` tool for the curator agent.
///
/// Archives a skill by setting its `lifecycleState` to `.retired` and recording
/// the merge relationship in `SkillUsageData.absorbedInto`. Only agent-created
/// skills that are not pinned may be archived.
///
/// - Parameters:
///   - skillRegistry: The registry to look up and replace skills.
///   - usageStore: The store for reading/writing skill usage data.
/// - Returns: A `ToolProtocol` instance named `curator_archive_skill`.
public func createCuratorArchiveTool(
    skillRegistry: SkillRegistry,
    usageStore: SkillUsageStore
) -> ToolProtocol {
    defineTool(
        name: "curator_archive_skill",
        description: "Archive a skill by retiring it. Optionally record which umbrella skill absorbed its content. Only agent-created, non-pinned skills can be archived.",
        inputSchema: [
            "type": "object",
            "properties": [
                "skillName": ["type": "string", "description": "Name of the skill to archive"],
                "absorbedInto": ["type": "string", "description": "Optional name of the umbrella skill that absorbed this skill's content. Omit or empty for pruning with no merge target."]
            ],
            "required": ["skillName"]
        ]
    ) { (input: CuratorArchiveInput, _: ToolContext) async -> String in
        let skillName = input.skillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skillName.isEmpty else {
            return reviewJSONResponse(["success": false, "error": "'skillName' must not be empty"] as [String: Any])
        }

        let usageData = await usageStore.getUsage(skillName: skillName)

        if usageData.provenance != .agentCreated {
            return reviewJSONResponse(["success": false, "error": "Cannot archive non-agent-created skill"] as [String: Any])
        }

        if usageData.pinned {
            return reviewJSONResponse(["success": false, "error": "Cannot archive pinned skill"] as [String: Any])
        }

        guard let skill = skillRegistry.find(skillName) else {
            return reviewJSONResponse(["success": false, "error": "Skill '\(skillName)' not found"] as [String: Any])
        }

        let archived = Skill(
            name: skill.name,
            description: skill.description,
            aliases: skill.aliases,
            userInvocable: skill.userInvocable,
            toolRestrictions: skill.toolRestrictions,
            modelOverride: skill.modelOverride,
            promptTemplate: skill.promptTemplate,
            whenToUse: skill.whenToUse,
            argumentHint: skill.argumentHint,
            baseDir: skill.baseDir,
            supportingFiles: skill.supportingFiles,
            lifecycleState: .retired
        )
        skillRegistry.replace(archived)

        let absorbedValue = input.absorbedInto?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAbsorbed = (absorbedValue?.isEmpty ?? true) ? nil : absorbedValue

        var updatedData = usageData
        updatedData.absorbedInto = resolvedAbsorbed
        updatedData.lastManagedAt = Date()
        do {
            try await usageStore.setUsage(skillName: skillName, data: updatedData)
        } catch {
            return reviewJSONResponse(["success": false, "error": "Failed to persist archive data: \(error.localizedDescription)"] as [String: Any])
        }

        return reviewJSONResponse([
            "success": true,
            "message": "Skill '\(skillName)' archived",
            "absorbedInto": resolvedAbsorbed as Any
        ] as [String: Any])
    }
}
