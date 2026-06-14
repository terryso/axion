# Test Plan

默认开发验证只运行单元测试，不运行集成测试或 E2E。所有新增测试使用 Swift Testing。

## Unit Test Scope

### SDK Unit Tests

Target package:

- `open-agent-sdk-swift`

Suggested suites:

- `SubAgentToolAliasTests`
- `DefaultSubAgentSpawnerToolFilteringTests`
- `SkillExecutionPromptContextTests`
- `SkillToolDeclarationCompatibilityTests`

Cases:

| Case | Assertion |
| --- | --- |
| `createTaskTool()` schema | tool name is `Task`; required fields include `prompt` and `description`; properties include `subagent_type` |
| Agent/Task alias shared behavior | `createAgentTool()` and `createTaskTool()` expose equivalent schema and route through the same spawner path |
| Agent compatibility unchanged | `createAgentTool()` still returns tool name `Agent` and existing schema |
| spawner detection with Agent | tool pool containing `Agent` gets non-nil spawner |
| spawner detection with Task | tool pool containing only `Task` gets non-nil spawner |
| child tool filtering | subagent tool pool excludes both `Agent` and `Task` |
| package context with filesystem skill | prompt contains `baseDir` and `supportingFiles` |
| package context omitted for built-in skill | prompt matches previous shape when no package metadata exists |
| args preservation | `User request: <args>` remains present and after package context |
| allowed-tools common names | `Read`, `Grep`, `WebSearch`, `ToolSearch`, `Agent`, `Task`, and `Skill` normalize to actual tool names |
| allowed-tools MCP names | `mcp__github__list_prs` is preserved as a filterable raw tool name |
| allowed-tools unknown names | all-unknown entries produce diagnostics and do not become unrestricted |
| subagent tools filter | `tools: ["Read", "Grep", "Glob"]` filters from the full tool pool, not a hand-built subset |
| subagent skills/MCP fields | `skills` and resolvable `mcpServers` references are wired in SDK 0.10.0; unresolved MCP references and deferred runtime controls produce diagnostics |

Mocking:

- Use mock `SubAgentSpawner` or SDK fake client where possible.
- Do not call real LLM APIs.
- Do not touch real user skill directories; use temporary directories.

### Axion Unit Tests

Target package:

- `AxionCLITests`

Suggested suites:

- `AgentBuilderSubagentToolRegistrationTests`
- `TaskSkillCompatibilityPromptTests`
- `SkillExecutionSubagentRegistryTests`
- `SkillExecutionToolProfileTests`

Cases:

| Case | Assertion |
| --- | --- |
| normal chat build tool names | `AgentBuildResult.agentOptions.tools` contains `Task` and `Agent` when not dry-run |
| dry-run build | tool names do not contain `Task`, `Agent`, `Skill`, `Bash`, write/edit side-effect tools, or side-effect MCP/custom tools |
| no-skills mode | Skill routing is disabled; Task registration policy matches architecture decision |
| slash router unchanged | built-in slash commands still win over same-named skill |
| unknown slash unchanged | unknown `/xxx` still routes to plain agent task |
| prompt guidance | system prompt includes slash-skill guidance when Task and Skill are available |
| direct skill registry | orchestrator skill execution path can see other discovered skills, not just itself |
| direct skill tool profile | lightweight skill execution includes eligible WebSearch/WebFetch/MCP/ToolSearch tools when config allows |
| ToolSearch policy | default provider/config policy can exclude ToolSearch; skill/subagent opt-in is honored only when policy allows it |
| MCP inheritance | skill agent receives the same configured MCP servers as normal agent unless disabled by config or dry-run |
| skill package sync diagnostic | missing `/bmad-bmm-*` command preserves the exact missing name and suggests `/skills` or alias/update |

Mocking:

- Do not call real `AgentBuilder.build()` in unit tests if it would resolve helper, MCP, API key, or real review infrastructure.
- Prefer extracting small pure helpers for tool selection and prompt fragments, then unit test those helpers directly.
- If testing `AgentBuilder` shape requires config, inject no-op stores and fake dependencies following existing `AgentBuilding` / `RunExecuting` patterns.

## Optional E2E

Location:

- `Tests/AxionE2ETests/Interactive/`

E2E should be skipped without API key.

Fixture idea:

1. Create temporary skill directory with:
   - `pipeline-test/SKILL.md`
   - `pipeline-test/references/workflow-steps.md`
   - `step-one/SKILL.md`
   - `step-two/SKILL.md`
2. Pipeline skill instructs two Task calls with `/step-one demo` and `/step-two demo`.
3. Step skills return deterministic short text and avoid file writes.
4. Build real chat agent with temp skill discovery directory.
5. Execute `/pipeline-test demo`.
6. Assert stream contains Task/Agent tool usage and both step summaries.

Additional optional fixture:

1. Add a temporary MCP-like in-process tool or fake namespaced tool `mcp__fixture__lookup`.
2. Create a skill with `allowed-tools: mcp__fixture__lookup, WebSearch, Task`.
3. Execute the skill and assert only those requested tools plus required runtime scaffolding are visible.

This E2E is not part of default validation because it needs a live model.

## Manual Acceptance

Preconditions:

- Updated `bmad-story-pipeline` installed.
- Axion resolved to `open-agent-sdk-swift` 0.10.0+.
- `~/.agents/skills/bmad-story-pipeline/SKILL.md` and `references/workflow-steps.md` both use the same current BMAD command names.
- Project `.agents/skills` contains `bmad-create-story`, `bmad-testarch-atdd`, `bmad-dev-story`, `bmad-code-review`, `bmad-testarch-trace`.
- API key configured.

Steps:

1. Run `axion`.
2. Run `/skills` and confirm pipeline and single-step BMAD skills are visible.
3. Run `/bmad-story-pipeline 1-1`.
4. Confirm the first Task child executes `/bmad-create-story 1-1 yolo`.
5. Confirm progress moves to the second Task only after the first child completes.
6. Force a missing skill in a copied fixture and confirm the pipeline stops with the missing command name visible.

Expected:

- The terminal shows Task tool use for each step.
- Each child summary returns to the parent.
- Failure stops the pipeline.
- Supporting file path is resolved from the skill package, not the current working directory.

## Default Verification Command

Use the project-defined unit-test command:

```bash
swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"
```

If SDK tests are changed in the local `open-agent-sdk-swift` checkout, run the relevant SDK unit test filters separately from that repository.

## Traceability

| Capability | Unit coverage | Optional E2E | Manual |
| --- | --- | --- | --- |
| CAP-1 | direct skill registry and Task availability tests | pipeline fixture | BMAD pipeline run |
| CAP-2 | Task schema and spawner detection tests | Task tool use appears | Task step visible |
| CAP-3 | prompt guidance and SkillTool inheritance tests | child step skill summaries | first BMAD step executes |
| CAP-4 | package context prompt tests | fixture supporting file read | workflow file resolved |
| CAP-5 | dry-run/no-skills registration tests | not required | dry-run spot check |
| CAP-6 | error result formatting tests | forced missing skill | missing skill stops pipeline |
| CAP-7 | test suites themselves | optional | default command passes |
| CAP-8 | tool profile and allowed-tools compatibility tests | MCP/search fixture | skill with MCP/search runs when allowed |
