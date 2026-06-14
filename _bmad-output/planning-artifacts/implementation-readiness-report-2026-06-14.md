---
project: axion
date: 2026-06-14
stepsCompleted:
  - document-discovery
  - prd-analysis
  - epic-coverage-validation
  - ux-alignment
  - epic-quality-review
  - final-assessment
includedFiles:
  - docs/epics/epic-40-claude-code-skill-subagent-compat.md
---

# Implementation Readiness Assessment Report

**Date:** 2026-06-14
**Project:** axion

## Step 1: Document Discovery

评估范围按用户确认收敛为 Epic-only readiness check。

**Included Documents:**

- `docs/epics/epic-40-claude-code-skill-subagent-compat.md` — Axion Epic 40: Claude Code Skill/Subagent Integration

**Excluded From Scope:**

- PRD documents
- Architecture documents
- UX design documents
- SDK Epic 29 full readiness assessment

**Notes:**

- SDK Epic 29 is considered only as a declared dependency/risk reference inside Epic 40.
- This report will not make a full PRD/Architecture/UX readiness judgment unless the scope is expanded.

## Step 2: PRD Analysis

PRD analysis is out of scope by explicit user instruction: only `docs/epics/epic-40-claude-code-skill-subagent-compat.md` should be checked.

### Functional Requirements

No PRD was included in the assessment scope, so no PRD-level FR list was extracted.

### Non-Functional Requirements

No PRD was included in the assessment scope, so no PRD-level NFR list was extracted.

### Additional Requirements

The only source for subsequent validation is Epic 40 itself. SDK Epic 29 may be treated as an external dependency referenced by Epic 40, but it is not independently assessed in this report.

### PRD Completeness Assessment

Not assessed. This is an Epic-only readiness check, so downstream findings evaluate whether Epic 40 is internally actionable rather than whether it fully covers a separate PRD.

## Step 3: Epic Coverage Validation

Because no PRD was included in scope, PRD FR coverage cannot be calculated. The validation below records Epic 40's internal goal-to-story coverage instead.

### Epic Goals Extracted

G1: 可运行 Claude Code workflow skill：`Task(...)` 由 SDK alias 支撑，Axion 工具池负责暴露该 tool。
G2: 复用 SDK runtime：Axion 不复制 `AgentTool`、`SubAgentSpawner`、`SkillTool` 逻辑，只组装和配置。
G3: 支持 skill 编排 skill：子代理收到 `Execute /skill-name args` 时能通过 `Skill` tool 执行对应 skill。
G4: 保留完整工具语义：direct skill agent 不因 lightweight path 默认失去 MCP、Web、search、domain tools。
G5: 安全和权限一致：dry-run、`--no-skills`、权限模式、tool allowlist、session allowlist 在普通 agent、skill agent、child agent 中保持一致。
G6: 可观察和可测试：用户能看到子任务开始、完成、失败和摘要；默认开发验证只跑 Axion 单元测试。

### Internal Coverage Matrix

| Goal | Epic 40 Coverage | Status |
| --- | --- | --- |
| G1 | Story 40.1, 40.2, 40.5 | Covered, depends on SDK Epic 29 |
| G2 | Story 40.1 | Covered |
| G3 | Story 40.3, 40.5 | Covered |
| G4 | Story 40.2 | Covered |
| G5 | Story 40.2 | Partially covered; session allowlist details are not independently specified |
| G6 | Story 40.4, 40.5, default test strategy | Covered |

### Missing Requirements

No PRD FRs were available for traceability validation. Within Epic 40 itself, the main traceability gap is that "session allowlist" is listed as a product goal but not expanded into concrete implementation tasks or acceptance criteria.

### Coverage Statistics

- Total PRD FRs: Not available
- FRs covered in epics: Not available
- Coverage percentage: Not available
- Epic 40 internal goals covered: 6/6
- Epic 40 internal goals with partial specification risk: 1/6

## Step 4: UX Alignment Assessment

### UX Document Status

Not found in the configured planning artifacts directory.

### UX Implied By Epic 40

UX is implied because Epic 40 affects interactive terminal behavior:

- Users run `/skills` and `/bmad-story-pipeline 1-1`.
- Users need visible child task start/completion/failure progress.
- Users need child summaries and retryable failure messages.
- Missing skills should produce actionable guidance.

### Alignment Issues

No standalone UX document exists to validate exact terminal output states, progress rendering, or failure message copy. Epic 40 includes functional expectations for visibility, but it does not specify exact rendering format, message hierarchy, or how nested child task progress should appear in compact vs verbose modes.

### Warnings

- UX documentation is missing even though user-facing terminal behavior is implied.
- This is not a hard blocker for implementation, but Story 40.4 should either include more concrete output examples or spawn a focused story before development begins.

## Step 5: Epic Quality Review

### Overall Epic Quality

Epic 40 has a clear technical boundary after the SDK split: SDK owns reusable runtime behavior, Axion owns host integration and BMAD acceptance. That boundary is directionally correct.

However, as an implementation-ready epic, it still has several readiness defects. The largest problem is that Epic 40 is now explicitly blocked by SDK Epic 29, while some Axion stories still assume SDK behavior without defining the exact dependency completion contract.

### Critical Violations

#### C1: Epic 40 is not independently implementable until SDK Epic 29 is done

Evidence:

- Epic 40 declares SDK Epic 29 as a prerequisite.
- Story 40.1 requires `createTaskTool()` and SDK direct skill package context.
- Stories 40.2-40.5 rely on `Task` alias, spawner injection, child filtering, and package context behavior.

Impact:

- Axion implementation can start only after SDK P0 behavior exists or is developed in the local SDK checkout first.
- If a story is created directly from 40.2 or later before SDK readiness, developers will hit missing APIs or unstable assumptions.

Recommendation:

- Treat Story 40.1 as a dependency gate.
- Add an explicit "SDK readiness checklist" to Story 40.1:
  - `createTaskTool()` exported.
  - spawner detection works for `Agent` or `Task`.
  - child tools filter both `Agent` and `Task`.
  - direct skill execution includes package context.
  - richer tool declaration diagnostics exist or unsupported declarations are explicitly handled.

### Major Issues

#### M1: Epic title and framing are still technical, not user-outcome first

The current title is `Claude Code Skill/Subagent Integration`. It describes implementation shape rather than the user outcome.

Recommendation:

- Consider a user-value title such as `Run Claude Code/BMAD Workflow Skills End-to-End in Axion`.
- Keep the technical integration scope in the body.

#### M2: Story 40.1 is a technical dependency story, not a user story

Story 40.1 is necessary but mostly says "consume SDK runtime". It does not itself deliver user-visible value.

Recommendation:

- Keep it as an enabling/dependency story, but label it explicitly as such.
- Do not mix it with user-facing acceptance. Its completion should be compile/API verification only.

#### M3: Story 40.2 is oversized and combines several independent concerns

Story 40.2 includes:

- extracting an Axion tool profile helper
- adding `Agent` / `Task` / `Skill`
- discovered `SkillRegistry`
- MCP tools
- Web tools
- `ToolSearch`
- dry-run side-effect filtering
- `--no-skills` behavior
- permission policy

This is too large for one implementation story and carries high regression risk.

Recommendation:

- Split into smaller stories:
  - 40.2a shared tool profile helper with current behavior parity.
  - 40.2b register `Agent` / `Task` / `Skill` in chat/run/skill paths.
  - 40.2c discovered skill registry for direct skill execution.
  - 40.2d MCP/Web/Search inheritance and provider policy.
  - 40.2e dry-run and `--no-skills` filtering rules.

#### M4: Session allowlist is listed as a goal but lacks implementation/acceptance coverage

Product goal G5 includes "session allowlist", but no story expands how session allowlist interacts with `Skill`, `Agent`, `Task`, MCP, or child agents.

Recommendation:

- Either remove "session allowlist" from the product goal or add acceptance criteria to Story 40.2.

#### M5: Story 40.4 output behavior is underspecified for a user-facing terminal feature

The story says progress should be visible and "至少显示" description/command/status, but does not define:

- exact event states
- compact vs verbose output
- indentation/nesting for child agent progress
- error rendering shape
- how repeated or nested tool events avoid noise

Recommendation:

- Add concrete output examples for success and failure.
- Define whether this is rendered by existing `SDKMessage` formatter or a new formatter branch.

#### M6: Story 40.5 mixes automated fixture acceptance and real local BMAD verification

Story 40.5 combines local skill package sync, test fixture design, and real `/bmad-story-pipeline` manual acceptance. These are related but not the same implementation unit.

Recommendation:

- Split fixture-based acceptance from real environment verification.
- Make real BMAD flow a manual acceptance checklist, not the only proof of correctness.

### Minor Concerns

#### m1: Some acceptance criteria depend on LLM behavior without deterministic test hooks

Examples:

- child prompt containing `Execute /bmad-create-story` should call `Skill` tool
- model should not print `Task(...)`

Recommendation:

- Add deterministic unit tests for prompt guidance and tool availability.
- Keep LLM/manual behavior as supplemental acceptance.

#### m2: SDK P0 vs P1 dependency wording is inconsistent

Story 40.1 says SDK Epic 29 P0 stories, while manual acceptance says SDK Epic 29 P0/P1.

Recommendation:

- Clarify the minimum required SDK subset before Axion implementation begins.

#### m3: Deferred SDK diagnostics propagation is not explicitly accepted in Axion

Epic 40 says SDK owns diagnostics, but Axion does not specify whether these diagnostics are surfaced in terminal output or logs.

Recommendation:

- Add an acceptance criterion that unsupported/deferred SDK diagnostics are visible in Axion output when relevant.

### Best Practices Checklist

| Check | Status | Notes |
| --- | --- | --- |
| Epic delivers user value | Partial | User value exists, but title/framing is technical |
| Epic can function independently | No | Blocked by SDK Epic 29 |
| Stories appropriately sized | Partial | Story 40.2 and 40.5 are oversized |
| No forward dependencies | Partial | External SDK dependency is explicit but must be gated |
| Clear acceptance criteria | Partial | Several ACs are good; output UX and allowlist need detail |
| Traceability maintained | Partial | Internal goal coverage exists; PRD traceability out of scope |

### Quality Review Conclusion

Epic 40 is directionally sound after the SDK split, but it is not yet ready for direct implementation as-is. It needs a dependency gate for SDK Epic 29 and story slicing before story creation/development begins.

## Summary and Recommendations

### Overall Readiness Status

**NEEDS WORK**

Epic 40 is directionally correct and the SDK/Axion boundary is now much cleaner, but it is not implementation-ready as currently written.

The main blocker is not conceptual. The blocker is planning granularity and dependency readiness:

- Axion work is explicitly blocked by SDK Epic 29.
- Story 40.2 is too large to be a reliable implementation story.
- User-facing progress/error output is underspecified.
- One stated goal, session allowlist consistency, does not have concrete acceptance coverage.

### Critical Issues Requiring Immediate Action

1. **Define SDK Epic 29 completion gate before Axion Story 40.2+ begins.**
   - Epic 40 should specify exactly which SDK APIs/behaviors must exist before Axion integration starts.

2. **Split Story 40.2 into smaller implementation stories.**
   - The current story mixes tool profile refactor, skill registry behavior, MCP/Web/Search policy, dry-run behavior, and `--no-skills` semantics.

3. **Add concrete terminal output examples for Story 40.4.**
   - The epic needs success/failure output examples for nested child task progress.

4. **Clarify session allowlist behavior or remove it from the goal.**
   - It is currently mentioned as a product goal but not specified as implementation behavior.

### Recommended Next Steps

1. Update Epic 40 Story 40.1 into an explicit SDK readiness gate with a checklist of required SDK Epic 29 behavior.
2. Split Story 40.2 into focused stories for tool profile parity, `Agent`/`Task`/`Skill` registration, discovered skill registry, MCP/Web/Search inheritance, and dry-run/no-skills policy.
3. Add output examples and error message shapes to Story 40.4.
4. Split Story 40.5 into automated fixture acceptance and real local BMAD manual verification.
5. Clarify the minimum SDK dependency level: P0 only, or P0 plus selected P1 diagnostics/tool declaration behavior.
6. Add an Axion acceptance criterion that SDK unsupported/deferred diagnostics are visible to the user when relevant.

### Final Note

This Epic-only assessment identified 11 issues across 5 categories:

- dependency readiness
- story sizing
- user-facing output/UX specificity
- deterministic testability
- traceability gaps inside Epic 40

Address the critical dependency gate and story slicing before creating implementation stories. After those changes, Epic 40 should be close to ready for BMAD story creation.

**Assessor:** Codex using `bmad-check-implementation-readiness`
**Completed:** 2026-06-14
