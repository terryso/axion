# Story 17.4: 隐式技能触发

Status: done

## Story

As a 用户,
I want 用自然语言描述意图时，LLM 自动匹配并执行对应技能,
So that 我不需要知道技能名称，只要描述我想做什么.

## Acceptance Criteria

1. **AC1: 隐式触发 — LLM 自动匹配技能**
   - **Given** SkillRegistry 中有 `polyv-live-cli` 技能，`whenToUse` 为 "用户需要管理直播频道、配置推流设置、管理商品、处理优惠券、查看直播数据或管理回放录像时使用"
   - **When** 用户运行 `axion run "帮我获取保利威最新的10个频道信息"`（无 `/skill-name` 前缀）
   - **Then** `formatSkillsForPrompt()` 将技能描述注入 system prompt 的 `## Available Skills` section
   - **And** section 中包含 Skill 工具使用指引，指导 LLM 在任务匹配 `TRIGGER when:` 时调用 Skill 工具
   - **And** SkillTool 已注册到 Agent 工具池，LLM 可调用 `Skill` 工具传入技能名执行

2. **AC2: Token 预算截断**
   - **Given** 技能列表有 10 个技能，`formatSkillsForPrompt()` token 预算为 500（SDK 默认值）
   - **When** 注入 system prompt
   - **Then** 按注册顺序列出技能，超出预算时截断尾部技能描述
   - **Note**：SDK `SkillRegistry.formatSkillsForPrompt()` 已实现此逻辑（Story 17.1 AC5），本 AC 只需验证

3. **AC3: `isAvailable()` 过滤**
   - **Given** 某技能 `isAvailable()` 返回 `false`
   - **When** `formatSkillsForPrompt()` 生成技能列表
   - **Then** 该技能不出现在列表中，LLM 无法发现和调用
   - **Note**：SDK `userInvocableSkills` 已过滤 `isAvailable() == true`，本 AC 只需验证

4. **AC4: `--no-skills` 禁用隐式触发**
   - **Given** 用户运行 `axion run --no-skills "帮我获取频道信息"`
   - **When** 启动 Agent
   - **Then** 不注入技能列表到 system prompt，SkillTool 不注册，LLM 无法调用技能
   - **Note**：已由 Story 17.1 实现，本 AC 只需回归验证

## Tasks / Subtasks

- [x] Task 1: 增强 `## Available Skills` section 添加 Skill 工具使用指引 (AC: #1)
  - [x] 1.1 修改 `RunCommand.buildFullSystemPrompt()` 中 `skillsPrompt` 注入逻辑
  - [x] 1.2 在 `## Available Skills` 标题后追加指引说明：告诉 LLM 当用户任务匹配 `TRIGGER when:` 条件时，调用 `Skill` 工具
  - [x] 1.3 指引内容包含：工具名 `Skill`、参数 `skill`（技能名）和 `args`（用户参数）、返回值包含 `prompt`（技能 prompt 模板）需作为后续执行指令

- [x] Task 2: 单元测试 (All ACs)
  - [x] 2.1 新建 `Tests/AxionCLITests/Services/ImplicitSkillTriggerTests.swift`
  - [x] 2.2 测试 AC1：system prompt 中 `## Available Skills` section 包含 Skill 工具使用指引
  - [x] 2.3 测试 AC1：skillsPrompt 非空时指引文本存在，为空时无 `## Available Skills` section
  - [x] 2.4 测试 AC2：formatSkillsForPrompt 多技能时按注册顺序列出（已有测试在 SkillIntegrationTests）
  - [x] 2.5 测试 AC3：isAvailable=false 的技能不出现在 formatSkillsForPrompt 输出中
  - [x] 2.6 测试 AC4：`--no-skills` 时 system prompt 无 `## Available Skills` section（回归验证）
  - [x] 2.7 测试指引文本包含关键信息：工具名 "Skill"、参数 "skill"、"args"

## Dev Notes

### 核心设计：隐式触发 = SkillTool + system prompt 指引

隐式触发不修改代码逻辑流程——Story 17.1 已注册 SkillTool 并注入 `formatSkillsForPrompt()` 到 system prompt。本 Story 的核心变更是增强 `## Available Skills` section 的格式，添加 LLM 友好的工具使用指引，让 LLM 知道何时及如何调用 Skill 工具。

### 当前实现（Story 17.1）

```swift
// RunCommand.swift:748-749
if !skillsPrompt.isEmpty {
    prompt += "\n\n## Available Skills\n\n\(skillsPrompt)"
}
```

当前 `formatSkillsForPrompt()` 输出格式：
```
- polyv-live-cli [args]: 保利威直播服务管理 TRIGGER when: 用户需要管理直播频道...
```

### 目标格式

```swift
if !skillsPrompt.isEmpty {
    prompt += """

    ## Available Skills

    When the user's task matches a skill's TRIGGER condition, call the `Skill` tool with the skill name and arguments. The tool returns a JSON with `prompt` (the skill's prompt template) — follow that prompt as your operating instructions for the rest of the task.

    \(skillsPrompt)
    """
}
```

LLM 看到的完整 section：
```
## Available Skills

When the user's task matches a skill's TRIGGER condition, call the `Skill` tool with the skill name and arguments. The tool returns a JSON with `prompt` (the skill's prompt template) — follow that prompt as your operating instructions for the rest of the task.

- polyv-live-cli [args]: 保利威直播服务管理 TRIGGER when: 用户需要管理直播频道...
```

### SkillTool 返回值（SDK 已实现）

当 LLM 调用 `Skill(skill: "polyv-live-cli", args: "获取最新10个频道信息")` 时，SkillTool 返回：
```json
{
  "success": true,
  "commandName": "polyv-live-cli",
  "prompt": "<技能的 promptTemplate 内容>",
  "allowedTools": ["bash", "read"],
  "baseDir": "/Users/nick/.claude/skills/polyv-live-cli",
  "supportingFiles": ["references.md", "templates/"]
}
```

LLM 应将 `prompt` 字段作为后续执行的指令。

### formatSkillsForPrompt() 已有能力（SDK）

- 按 `userInvocable == true` + `isAvailable() == true` 过滤
- 每个技能格式：`- {name}{argumentHint}: {description} TRIGGER when: {whenToUse}`
- Token 预算默认 500 tokens（`promptTokenBudget * 4` chars）
- 超预算截断尾部技能
- 描述超 250 字符截断加 `...`

### 显式触发 vs 隐式触发对比

| 特性 | 显式触发（17.3） | 隐式触发（17.4） |
|------|-----------------|-----------------|
| 触发方式 | `/skill-name` 前缀 | 自然语言匹配 TRIGGER |
| systemPrompt | 使用 promptTemplate 替换 | 追加技能列表到末尾 |
| SkillTool 角色 | 不使用（显式路径） | LLM 调用获取 prompt |
| promptTemplate 来源 | 直接从 explicitSkill 取 | 从 SkillTool 返回值取 |
| toolRestrictions | 在 AgentOptions.allowedTools 设置 | SkillTool 返回给 LLM 参考 |
| modelOverride | 在 AgentOptions.model 设置 | SkillTool 返回给 LLM 参考 |

### 现有文件需要修改

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Sources/AxionCLI/Commands/RunCommand.swift` | 修改 | 增强 `buildFullSystemPrompt` 中 skillsPrompt 注入逻辑 |

### 新增文件

| 文件 | 说明 |
|------|------|
| `Tests/AxionCLITests/Services/ImplicitSkillTriggerTests.swift` | 隐式触发单元测试 |

### RunCommand 变更细节

修改 `buildFullSystemPrompt` 方法中 skillsPrompt 注入部分（当前位于 line 748-749）：

**当前代码：**
```swift
if !skillsPrompt.isEmpty {
    prompt += "\n\n## Available Skills\n\n\(skillsPrompt)"
}
```

**目标代码：**
```swift
if !skillsPrompt.isEmpty {
    prompt += """

    ## Available Skills

    When the user's task matches a skill's TRIGGER condition, call the `Skill` tool with the skill name and arguments. The tool returns a JSON with `prompt` (the skill's prompt template) — follow that prompt as your operating instructions for the rest of the task.

    \(skillsPrompt)
    """
}
```

变更仅限 `buildFullSystemPrompt` 方法内部，不影响 `run()` 方法的其他逻辑。

### 测试策略

- Swift Testing 框架（`import Testing`, `@Suite`, `@Test`, `#expect`）
- 测试使用 mock SkillRegistry + 临时目录
- `buildFullSystemPrompt` 是 `internal` 方法，可直接测试
- 回归验证 AC2/AC3/AC4 的已有行为

测试用例覆盖：
- 指引文本存在性：验证 `## Available Skills` section 包含 "Skill" 工具名和 "TRIGGER" 关键词
- 指引文本完整性：验证包含工具使用说明（skill 参数、prompt 返回值）
- isAvailable 过滤：注册 isAvailable=false 的技能，验证不出现在 formatSkillsForPrompt 输出
- --no-skills 回归：验证 noSkills 时无 `## Available Skills` section

### 关键设计决策

- **不修改 SDK 代码** — SkillTool、SkillRegistry、formatSkillsForPrompt() 均为 SDK 类型，行为正确
- **不修改 SkillTool** — LLM 通过 SkillTool 的 tool description 和返回值获取足够信息
- **指引用英文** — system prompt 全英文，与 planner-system.md 保持一致
- **指引简洁** — 两句话足够指导 LLM，不浪费 token
- **保持显式触发路径不变** — 隐式触发只影响非 `/skill-name` 的普通 Agent 流程

### 反模式提醒

- **禁止**修改 SDK 代码 — SkillTool、SkillRegistry、formatSkillsForPrompt() 均已正确实现
- **禁止**在指引中列举所有工具名 — LLM 已从 tool list 获取工具信息
- **禁止**修改 `run()` 方法中 SkillTool 注册逻辑 — `createSkillTool(registry:)` 已在 Story 17.1 正确注册
- **禁止**修改 `formatSkillsForPrompt()` 调用逻辑 — `noSkills ? "" : skillRegistry.formatSkillsForPrompt()` 已正确处理
- **禁止**在测试中依赖真实 `~/.claude/skills/` 目录
- **禁止**修改显式触发路径（`explicitSkill` 分支）— 隐式触发只影响 else 分支

### 与其他 Story 的关系

- **17.1（已完成）** — 提供 SkillRegistry、SkillTool、formatSkillsForPrompt 基础设施，本 Story 在其之上增强指引
- **17.2（已完成）** — 提供 `/skill-name` 解析、双轨查找，隐式触发不经过此路径
- **17.3（已完成）** — 显式触发修改 `explicitSkill` 分支，与本 Story 的 `else` 分支正交
- **18.1（内置桌面技能）** — 会使用隐式触发能力，内置技能的 whenToUse 将被 LLM 自动匹配

### NFR 参考

- NFR45: formatSkillsForPrompt() 生成的技能描述占用 system prompt < 500 token — SDK 默认 promptTokenBudget=500，指引文本约 50 tokens，总预算可控
- NFR46: 隐式触发场景下，SkillTool 调用增加的延迟 < 1 轮 LLM 交互 — SkillTool 是内存操作，无 IO

### References

- [Source: epics.md — Epic 17 Story 17.4 隐式技能触发]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift — buildFullSystemPrompt skillsPrompt 注入（line 748-749）、SkillTool 注册（line 233-236）]
- [Source: OpenAgentSDK/Tools/Advanced/SkillTool.swift — createSkillTool、SkillTool 执行逻辑]
- [Source: OpenAgentSDK/Tools/SkillRegistry.swift — formatSkillsForPrompt()、userInvocableSkills]
- [Source: OpenAgentSDK/Types/SkillTypes.swift — Skill struct（whenToUse、isAvailable）]
- [Source: OpenAgentSDK/Skills/SkillLoader.swift — whenToUse 从 frontmatter "when-to-use" 加载]
- [Source: _bmad-output/implementation-artifacts/17-1-runcommand-integrate-skillregistry.md — Story 17.1 完成记录]
- [Source: _bmad-output/implementation-artifacts/17-3-explicit-skill-name-trigger.md — Story 17.3 完成记录]
- [Source: Tests/AxionCLITests/Commands/SkillIntegrationTests.swift — Story 17.1 技能集成测试]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- Red phase: 3 tests failed as expected (TRIGGER/args/prompt not in prompt)
- Green phase: Added Skill tool usage guide to buildFullSystemPrompt, all 8 tests pass
- Regression: 1667 tests pass, 0 failures

### Completion Notes List

- Modified `RunCommand.buildFullSystemPrompt()` to inject Skill tool usage guide in `## Available Skills` section
- Guide tells LLM: when task matches TRIGGER condition, call `Skill` tool with `skill` and `args` params; tool returns `prompt` to follow as instructions
- 8 unit tests in `ImplicitSkillTriggerTests.swift` covering AC1-AC4 and guide completeness
- No SDK changes needed — SkillTool, SkillRegistry, formatSkillsForPrompt() all working correctly

### File List

- `Sources/AxionCLI/Commands/RunCommand.swift` — Modified: enhanced skillsPrompt injection with tool usage guide
- `Tests/AxionCLITests/Services/ImplicitSkillTriggerTests.swift` — New: 8 unit tests for implicit skill trigger

### Change Log

- 2026-05-18: Story 17.4 implementation complete. Added Skill tool usage guide to `## Available Skills` section in system prompt, enabling LLM to automatically match and invoke skills via natural language (AC1). Verified token budget (AC2), isAvailable filter (AC3), --no-skills regression (AC4).

## Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.7 | **Date:** 2026-05-18

**Issues Found:** 1 High, 3 Medium, 1 Low → All auto-fixed

### Fixes Applied

1. **[HIGH] `testGuideMentionsParameters` 误报风险** — 改用 backtick 精确匹配 (`\`skill\`` / `\`args\``) 替代 `contains("skill")`，避免匹配标题中的 "Skills"
2. **[MEDIUM] AC4 测试同义反复** — 改为模拟 `noSkills` 代码路径：`cmd.noSkills ? "" : "dummy"`，验证 flag 实际控制 skillsPrompt
3. **[MEDIUM] Story 重复空 section** — 删除末尾重复的 Debug Log References / Completion Notes List / File List
4. **[MEDIUM] 指南文本 args 可选标注** — 添加 "required" / "optional" 标注：`\`skill\` (skill name, required) and \`args\` (user arguments, optional)`
5. **[LOW] 测试输入格式** — 更新 AC1 测试使用更真实的 `formatSkillsForPrompt` 输出格式（含 `[args]` 和 `TRIGGER when:`）

### Regression

- 8 ImplicitSkillTrigger tests: PASS
- 1667 unit tests: PASS (1 pre-existing issue unrelated to Story 17.4)
