# Implementation Plan

## Phase 1: SDK Agent/Task Subagent Tool Alias

Primary files:

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/Advanced/AgentTool.swift`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/DefaultSubAgentSpawner.swift`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/OpenAgentSDK.swift`

Tasks:

1. Extract the shared body of `createAgentTool()` into an internal helper that can build a subagent launcher tool with a configurable public name.
2. Keep `createAgentTool()` returning tool name `Agent`.
3. Add `createTaskTool()` returning tool name `Task`, with the same schema and behavior. Treat `Task` as a Claude Code alias for `Agent`, not as a separate runtime abstraction.
4. Update spawner detection so `Agent` or `Task` enables `ToolContext.agentSpawner`.
5. Update child tool filtering so subagents remove both `Agent` and `Task`.
6. Preserve existing enhanced Agent fields (`mcpServers`, `skills`, `run_in_background`, `isolation`, `team_name`, `resume`) in the shared schema; unsupported/deferred fields must produce diagnostics when requested instead of silently doing nothing where feasible.
7. Export `createTaskTool()` from the SDK module surface if needed.

Acceptance:

- A tool pool containing only `Task` gets a non-nil spawner.
- A tool pool containing `Agent` and `Task` does not pass either launcher into child tools by default.
- Existing `Agent` tool tests keep passing.
- Documentation/comments call out `Task` as alias of `Agent`.

## Phase 2: Direct Skill Package Context

Primary file:

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift`

Tasks:

1. Extract prompt construction from `resolveSkillForExecution(_:, args:)` into a small helper.
2. Append compact package context when `skill.baseDir` or `skill.supportingFiles` exists.
3. Preserve current `User request: <args>` suffix.
4. Add unit tests around prompt construction rather than real model execution.

Prompt shape:

```text
<skill.promptTemplate>

---
Skill package context:
- baseDir: <baseDir>
- supportingFiles:
  - references/workflow-steps.md

Resolve bare supporting-file paths relative to baseDir. Read supporting files only when the skill instructions require them.

---
User request: <args>
```

Acceptance:

- A filesystem skill with `supportingFiles = ["references/workflow-steps.md"]` produces a prompt containing `baseDir` and that supporting file.
- A programmatic built-in skill with no package metadata keeps the old prompt shape.

## Phase 3: Shared Tool Profile for Chat, Skill, and Subagent Paths

Primary files:

- `Sources/AxionCLI/Services/AgentBuilder.swift`
- `Sources/AxionCLI/Services/AgentBuilder+PromptBuilding.swift`
- `Sources/AxionCLI/Services/AxionRuntime+SkillExecution.swift`
- SDK `ToolRegistry.swift` / skill filtering helpers if the policy belongs in SDK

Tasks:

1. Extract tool-pool assembly from `AgentBuilder.build()` into a pure helper that can be reused by normal chat/run and `buildSkillAgent()`.
2. Append `createAgentTool()` and `createTaskTool()` together when subagents are enabled and not dry-run.
3. Preserve dry-run semantics by excluding side-effect tools, including `Agent`, `Task`, `Skill`, `Bash`, write/edit tools, storage execution, app uninstall execution, and non-read-only MCP tools.
4. Replace `buildSkillAgent()`'s single-skill registry with the discovered registry when executing filesystem skills that may orchestrate other skills.
5. Register `Skill`, `Agent`, and `Task` in the lightweight skill path when allowed.
6. Inherit MCP/Web/Search availability from the same build profile used by normal agents. Do not keep MCP disabled merely because this is skill execution.
7. Convert the current hard-coded `ToolSearch` exclusion into provider/config policy. Keep the current default if needed for GLM stability, but allow skill/subagent declarations to request `ToolSearch`.
8. Add system prompt guidance for slash-form skill execution inside Task/Agent prompts when `Skill` and `Task` are both available.
9. Ensure `AgentBuildResult.agentOptions.tools` exposes expected tool names for unit assertions.

Acceptance:

- Normal chat build includes `Task` and `Agent` outside dry-run.
- Direct skill build includes the same eligible tool classes as normal build, then applies skill restrictions.
- Dry-run excludes `Task`, `Agent`, `Skill`, `Bash`, write/edit tools, and side-effect MCP/custom tools.
- Direct skill execution path can execute an orchestrator skill that invokes sub-skills.
- A skill requiring WebSearch, WebFetch, ToolSearch, or MCP can receive those tools when config and permissions allow.

## Phase 4: Skill/Subagent Tool Declaration Compatibility

Primary files:

- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/SkillTypes.swift`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Skills/SkillLoader.swift`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Core/Agent.swift`
- `.build/checkouts/open-agent-sdk-swift/Sources/OpenAgentSDK/Tools/ToolRestrictionStack.swift`

Tasks:

1. Replace or extend enum-only `ToolRestriction` with a representation that preserves raw tool names and normalized aliases.
2. Support Claude Code common tool spellings such as `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Bash`, `WebFetch`, `WebSearch`, `ToolSearch`, `Agent`, `Task`, and `Skill`.
3. Support MCP namespaced tools such as `mcp__github__list_prs` and permission patterns such as `Bash(git diff:*)` as raw entries even if fine-grained matching is deferred.
4. When parsing `allowed-tools`, surface unsupported or unrecognized entries in diagnostics; do not silently convert an all-unknown list into no restriction.
5. Apply skill restrictions to the complete assembled tool pool after base/custom/MCP deduplication.
6. Make subagent `tools` and `disallowedTools` use the same normalization/filtering path as skill `allowed-tools`.

Acceptance:

- `allowed-tools: WebSearch, mcp__github__list_prs, Task` filters to those tools when present.
- `allowed-tools: UnknownTool` reports a diagnostic and does not become unrestricted.
- Subagent `tools: ["Read", "Grep", "Glob"]` still provides read-only analysis behavior.
- Fine-grained patterns that are parsed but not enforced are explicitly marked as unsupported/deferred.

## Phase 5: Error Handling and Output

Primary files:

- SDK `AgentTool.swift` or new shared subagent tool file
- Axion output formatting if tool previews need labels

Tasks:

1. Include `description` in the Task tool result or progress metadata where available.
2. If child result is an error, return `isError: true` and preserve child error text.
3. If `prompt` contains an executable slash skill command, include that command in the error message.
4. Avoid adding custom progress channels until existing `SDKMessage.toolUse`, `toolProgress`, and tool result formatting prove insufficient.

Acceptance:

- Parent output identifies which Task failed.
- Manual retry command is visible when derivable from prompt.

## Phase 6: Skill Package Sync and Operator Guidance

Primary files:

- Existing docs or release notes after implementation
- Optional diagnostic output in Task child failure

Tasks:

1. Document that old BMAD command names must be resolved through aliases or updated skill packages.
2. Before manual acceptance, verify both `~/.agents/skills/bmad-story-pipeline/SKILL.md` and `references/workflow-steps.md` use the same command names; the reference file may be fixed while hard-coded Task prompts in `SKILL.md` remain stale.
3. Do not hard-code `bmad-bmm-*` to `bmad-*` mappings in Axion.
4. When SkillTool reports `Skill "<name>" not found`, preserve that exact name and suggest `/skills` for discovery.

Acceptance:

- Missing old BMAD names fail loudly and explain the remediation.
- Updated GitHub skill names work without Axion-specific mapping.

## Phase 7: Deferred Claude Code Parity Work

Record these as follow-ups, not blockers for the BMAD pipeline MVP:

1. Filesystem subagent discovery for `.claude/agents/*.md` and optionally `.agents/agents/*.md`.
2. Subagent reference MCP server resolution instead of only inline MCP configs.
3. Full `skills` wiring on subagent definitions.
4. Background/resume/isolation/team semantics for Agent SDK fields.
5. Skill listing budgets, visibility overrides, and model-invocation controls similar to Claude Code's large skill library behavior.

## Suggested File-Level Change Summary

SDK:

- `AgentTool.swift`: add shared factory and `createTaskTool()`.
- `Agent.swift`: treat `Task` as spawner-capable; append skill package context.
- `DefaultSubAgentSpawner.swift`: filter both subagent launchers.
- `SkillLoader.swift` / `SkillTypes.swift`: preserve raw tool names and MCP/custom tool restrictions.
- SDK tests: add focused unit coverage.

Axion:

- `AgentBuilder.swift`: register `Agent` and `Task` with correct guards; reuse one tool profile for normal and skill agents.
- `AgentBuilder+PromptBuilding.swift`: add Task slash skill guidance.
- `AxionRuntime+SkillExecution.swift` or builder protocol: ensure direct skill execution has full discovered registry and eligible MCP/Web/Search tools when needed.
- `Tests/AxionCLITests/...`: add mock-based registration and routing tests.

## Rollout Strategy

1. Land SDK changes first, because Axion cannot reliably expose `Task` without SDK spawner support.
2. Land Axion registration behind the same non-dry-run guard as other side-effect tools.
3. Add unit tests before any live API E2E.
4. Run the project unit test command only.
5. Optionally run a manual live pipeline with a throwaway story after unit tests pass.

## Risks

| Risk | Mitigation |
| --- | --- |
| Model still prints `Task(...)` instead of calling tool | Tool name must be exactly `Task`; system prompt should say Claude Code Task snippets map to the `Task` tool |
| Child agent recurses by calling Task again | Filter `Agent` and `Task` out of child tools by default |
| Child agent treats `/skill` as chat | Add slash-skill guidance and ensure SkillTool is inherited |
| Direct skill cannot find references | Append package context in direct skill prompt |
| Dry-run becomes unsafe | Explicitly exclude Task and Agent in dry-run tool filtering |
| Skill requiring MCP/search silently loses tools | Reuse full tool profile and make ToolSearch/MCP policy configurable |
| `allowed-tools` unknown names become unrestricted | Preserve raw names and report diagnostics |
| Old BMAD names fail | Prefer skill aliases or skill package update; produce actionable missing-skill errors |
