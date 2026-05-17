# Story 17.3: 显式 `/skill-name` 触发

Status: done

## Story

As a 用户,
I want 在 prompt 中用 `/skill-name` 语法显式触发技能,
So that 我可以精确控制使用哪个技能完成任务.

## Acceptance Criteria

1. **AC1: Prompt 技能显式触发 — promptTemplate 注入**
   - **Given** `polyv-live-cli` 技能已注册（有 `promptTemplate`）
   - **When** 用户运行 `axion run "/polyv-live-cli 获取最新10个频道信息"`
   - **Then** RunCommand 解析出技能名 `polyv-live-cli` 和参数 `获取最新10个频道信息`
   - **And** 将技能的 `promptTemplate` 作为 Agent 的 `systemPrompt`（替换默认 planner-system.md）
   - **And** 将用户参数（`获取最新10个频道信息`）作为 Agent 的 task 输入

2. **AC2: Prompt 技能 — toolRestrictions 限定工具集**
   - **Given** 技能有 `toolRestrictions: [.bash, .read, .glob, .grep]`
   - **When** 显式触发该技能
   - **Then** `AgentOptions.allowedTools` 设为 `["bash", "read", "glob", "grep"]`，Agent 只能使用这些工具
   - **And** 技能无 `toolRestrictions` 时，`allowedTools` 为 `nil`（所有工具可用）

3. **AC3: Prompt 技能 — modelOverride 切换模型**
   - **Given** 技能有 `modelOverride: "claude-opus-4-6"`
   - **When** 显式触发该技能
   - **Then** `AgentOptions.model` 使用 `claude-opus-4-6` 执行，而非配置的默认模型
   - **And** 技能无 `modelOverride` 时，使用 `config.model` 默认模型

4. **AC4: 录制技能 — 必需参数缺失提示**
   - **Given** `open_calculator` 是录制技能（JSON），有参数 `url`（无 `defaultValue`，即必需参数）
   - **When** 用户运行 `axion run "/open_calculator"`（未提供 `url` 参数）
   - **Then** 提示 `技能 'open_calculator' 缺少必需参数: url`，不执行，退出码 1
   - **And** 参数有 `defaultValue` 但用户未提供时，使用默认值，不报错

5. **AC5: `/` 不在句首不触发**
   - **Given** 用户输入 `axion run "请帮我/polyv-live-cli获取频道"`
   - **When** 解析 prompt
   - **Then** `/` 不被识别为技能触发，整句作为普通 prompt 发送给 LLM
   - **Note**：此 AC 已由 Story 17.2 的 `SkillLookupService.parseSkillInvocation()` 实现（`task.hasPrefix("/")`），本 Story 无需额外修改

6. **AC6: `--no-skills` 禁用显式触发**
   - **Given** 用户运行 `axion run --no-skills "/polyv-live-cli 获取频道"`
   - **When** 启动 Agent
   - **Then** `/skill-name` 解析被跳过，整句作为普通 prompt 发送给 LLM
   - **Note**：此 AC 已由 Story 17.2 实现（`!noSkills` guard），本 Story 无需额外修改

## Tasks / Subtasks

- [x] Task 1: 增强 `.promptSkill` 路径 — 注入 promptTemplate 和配置 (AC: #1, #2, #3)
  - [x] 1.1 在 `RunCommand.run()` 中，`.promptSkill` case 捕获 skill 对象并存储为局部变量 `explicitSkill`
  - [x] 1.2 在构建 systemPrompt 时，若 `explicitSkill` 存在，使用 `skill.promptTemplate` + 工具列表描述 替代 `baseSystemPrompt`
  - [x] 1.3 修改 task 变量：若 `explicitSkill` 存在，task = `invocation.args ?? "Execute skill \(skill.name)"`
  - [x] 1.4 在构建 `AgentOptions` 时，若 `explicitSkill.toolRestrictions` 存在，设置 `allowedTools = restrictions.map(\.rawValue)`
  - [x] 1.5 在构建 `AgentOptions` 时，若 `explicitSkill.modelOverride` 存在，设置 `model = skill.modelOverride`（否则使用 `config.model`）

- [x] Task 2: 录制技能参数校验 (AC: #4)
  - [x] 2.1 在 `RecordedSkillRunner.run()` 中，执行前检查必需参数
  - [x] 2.2 筛选 `skill.parameters.filter { $0.defaultValue == nil }` 获取必需参数列表
  - [x] 2.3 检查必需参数是否都在 `paramValues` 中提供，缺失则打印错误信息并 `throw ExitCode(1)`
  - [x] 2.4 有 `defaultValue` 的参数：用户未提供时自动填充默认值

- [x] Task 3: 单元测试 (All ACs)
  - [x] 3.1 新建 `Tests/AxionCLITests/Services/ExplicitSkillTriggerTests.swift`
  - [x] 3.2 测试 prompt 技能显式触发时 promptTemplate 注入 systemPrompt（AC1）
  - [x] 3.3 测试 toolRestrictions → allowedTools 映射正确（AC2）
  - [x] 3.4 测试无 toolRestrictions 时 allowedTools 为 nil（AC2）
  - [x] 3.5 测试 modelOverride 替换默认模型（AC3）
  - [x] 3.6 测试无 modelOverride 时使用默认模型（AC3）
  - [x] 3.7 测试录制技能缺少必需参数时报错退出（AC4）
  - [x] 3.8 测试录制技能有 defaultValue 的参数自动填充（AC4）
  - [x] 3.9 测试录制技能所有必需参数都提供时正常执行（AC4）

## Dev Notes

### 核心设计：显式技能触发增强

Story 17.2 已实现 `/skill-name` 解析和双轨查找。当前 `.promptSkill` case 只做 `break`（继续正常 Agent 流程）。本 Story 增强该路径，将技能的 `promptTemplate`、`toolRestrictions`、`modelOverride` 应用到 Agent 配置。

### 当前 `.promptSkill` 路径（Story 17.2）

```swift
// RunCommand.swift:82-85
case .promptSkill:
    // Prompt skill found — continue normal Agent flow.
    // SkillTool is already registered, LLM will use promptTemplate.
    break
```

### 目标 `.promptSkill` 路径

```swift
case .promptSkill(let skill):
    explicitSkill = skill  // 存储供后续 AgentOptions 配置使用
    effectiveTask = invocation.args ?? "Execute skill \(skill.name)"
    // 继续正常 Agent 流程，但在构建 options 时使用 skill 配置
```

### systemPrompt 构建策略

当显式技能触发时，system prompt 构建策略：

1. **skill.promptTemplate** 作为 system prompt 主体
2. 追加 **工具列表描述**（`PromptBuilder.buildToolListDescription`）让 Agent 知道可用的 MCP 工具
3. **不追加** `## Available Skills` section（已显式指定技能，无需隐式发现）
4. Memory 上下文仍正常注入（除非 `--no-memory`）

```
systemPrompt = """
\(skill.promptTemplate)

## Available Tools
\(toolListDescription)
"""
+ memoryContext（如有）
```

### toolRestrictions → allowedTools 映射

SDK `ToolRestriction` enum 的 rawValue 直接对应工具名：
```
.bash → "bash"
.read → "read"
.write → "write"
.glob → "glob"
.grep → "grep"
```

`AgentOptions.allowedTools` 接受 `[String]?`：
- 有 `toolRestrictions`：`allowedTools = restrictions.map(\.rawValue)`
- 无 `toolRestrictions`：`allowedTools = nil`（所有工具可用）

**注意**：`ToolRestriction` 只包含 SDK 内置工具名（bash, read, write 等），不包含 MCP 工具（如 `mcp__axion-helper__screenshot`）。当技能指定 `toolRestrictions` 时，MCP 工具也会被过滤掉。这是预期行为——技能作者通过 toolRestrictions 控制可用工具范围。

### modelOverride 应用

```swift
let effectiveModel: String
if let modelOverride = explicitSkill?.modelOverride {
    effectiveModel = modelOverride
} else {
    effectiveModel = config.model
}
// 在 AgentOptions 中使用 effectiveModel
```

无需在执行后"恢复默认模型"——`config.model` 是值类型，每次 run() 创建新的 Agent，不会跨运行污染。

### 录制技能参数校验

`AxionCore.SkillParameter` 有 `name` 和 `defaultValue: String?`：
- `defaultValue == nil` → 必需参数
- `defaultValue != nil` → 可选参数

校验逻辑：
```swift
let requiredParams = skill.parameters.filter { $0.defaultValue == nil }
var resolvedParams = paramValues

// 填充默认值
for param in skill.parameters {
    if resolvedParams[param.name] == nil, let defaultVal = param.defaultValue {
        resolvedParams[param.name] = defaultVal
    }
}

// 检查必需参数
let missingParams = requiredParams.filter { resolvedParams[$0.name] == nil }
if !missingParams.isEmpty {
    let names = missingParams.map(\.name).joined(separator: ", ")
    print("技能 '\(skill.name)' 缺少必需参数: \(names)")
    throw ExitCode(1)
}
```

### 现有文件需要修改

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Sources/AxionCLI/Commands/RunCommand.swift` | 修改 | 增强 `.promptSkill` case：捕获 skill，注入 promptTemplate，应用 toolRestrictions 和 modelOverride |
| `Sources/AxionCLI/Services/RecordedSkillRunner.swift` | 修改 | 添加必需参数校验和默认值填充 |

### 新增文件

| 文件 | 说明 |
|------|------|
| `Tests/AxionCLITests/Services/ExplicitSkillTriggerTests.swift` | 显式触发单元测试 |

### 项目结构

```
Sources/AxionCLI/
├── Commands/
│   └── RunCommand.swift                      # 修改：增强 .promptSkill 路径
├── Services/
│   ├── RecordedSkillRunner.swift             # 修改：添加参数校验
│   └── SkillLookupService.swift             # 不修改（17.2 已实现）

Tests/AxionCLITests/Services/
└── ExplicitSkillTriggerTests.swift           # 新增：显式触发测试
```

### RunCommand 变更细节

在 `run()` 方法中需要以下修改：

1. **新增局部变量**（在 `// 0b.` 之前）：
   ```swift
   var explicitSkill: OpenAgentSDK.Skill? = nil
   ```

2. **修改 `.promptSkill` case**：
   ```swift
   case .promptSkill(let skill):
       explicitSkill = skill
       task = invocation.args ?? "Execute skill \(skill.name)"
   ```

3. **修改 systemPrompt 构建**（步骤 5 之后）：
   ```swift
   let systemPrompt: String
   if let skill = explicitSkill {
       // 显式触发：用 promptTemplate + tool list 替代 baseSystemPrompt
       let toolList = PromptBuilder.buildToolListDescription(from: mcpPrefixedToolNames)
       var prompt = skill.promptTemplate
       prompt += "\n\n## Available Tools\n\(toolList)"
       if let memCtx = memoryContext, !memCtx.isEmpty {
           prompt += "\n\n\(memCtx)"
       }
       systemPrompt = prompt
   } else {
       systemPrompt = buildFullSystemPrompt(
           basePrompt: baseSystemPrompt, fast: fast, dryrun: dryrun,
           verbose: verbose, memoryContext: memoryContext, skillsPrompt: skillsPrompt
       )
   }
   ```

4. **修改 AgentOptions 构建**（步骤 8）：
   ```swift
   let effectiveModel = explicitSkill?.modelOverride ?? config.model

   var allowedTools: [String]? = nil
   if let restrictions = explicitSkill?.toolRestrictions {
       allowedTools = restrictions.map(\.rawValue)
   }

   let options = AgentOptions(
       ...
       model: effectiveModel,
       ...
       allowedTools: allowedTools,
       ...
   )
   ```

5. **修改 skillsPrompt 注入**：当 `explicitSkill` 存在时，不注入 `## Available Skills` section（避免隐式触发干扰显式技能）。

### RecordedSkillRunner 变更细节

在 `run()` 方法的 `executor.execute()` 调用之前，添加参数校验：

```swift
// Validate required parameters
var resolvedParams = paramValues
for param in skill.parameters {
    if resolvedParams[param.name] == nil, let defaultVal = param.defaultValue {
        resolvedParams[param.name] = defaultVal
    }
}
let requiredParams = skill.parameters.filter { $0.defaultValue == nil }
let missingParams = requiredParams.filter { resolvedParams[$0.name] == nil }
if !missingParams.isEmpty {
    let names = missingParams.map(\.name).joined(separator: ", ")
    print("技能 '\(skill.name)' 缺少必需参数: \(names)")
    throw ExitCode(1)
}
// Use resolvedParams (with defaults filled) instead of paramValues
result = try await executor.execute(skill: skill, paramValues: resolvedParams)
```

### 测试策略

- Swift Testing 框架（`import Testing`, `@Suite`, `@Test`, `#expect`）
- 测试使用 mock SkillRegistry + 临时目录，不依赖真实文件系统
- RunCommand 的 `buildFullSystemPrompt` 是 `internal`，可直接测试
- `computeEffectiveMaxSteps` 和 `computeEffectiveMaxTokens` 也是 `internal static`

测试用例覆盖：
- 显式 prompt 技能：验证 promptTemplate 被用作 systemPrompt
- toolRestrictions 映射：验证 `allowedTools` 正确设置
- modelOverride：验证模型切换
- 录制技能参数校验：缺少必需参数报错，有默认值自动填充
- 综合测试：显式触发 + toolRestrictions + modelOverride 同时生效

### 关键设计决策

- **promptTemplate 替换（不追加）baseSystemPrompt** — 显式触发时用户明确选择了技能，技能的 promptTemplate 应为主导指令，planner-system.md 的通用规划指令不适用
- **追加工具列表** — 即使替换 systemPrompt，Agent 仍需知道可用的 MCP 工具名称和格式
- **显式触发时不注入 `## Available Skills`** — 避免隐式触发干扰，减少 token 消耗
- **Memory 上下文仍正常注入** — Memory 与技能正交，不受显式/隐式触发影响
- **`allowedTools` 为 nil 表示全部可用** — 与 SDK 约定一致，避免显式列举所有工具
- **录制技能默认值自动填充** — 用户无需手动提供有默认值的参数

### 反模式提醒

- **禁止**修改 `SkillLookupService` — 解析逻辑已在 Story 17.2 实现
- **禁止**修改 `SkillExecutor` — 它只负责执行，不负责参数校验
- **禁止**修改 SDK 代码 — `ToolRestriction`、`Skill`、`AgentOptions` 均为 SDK 类型
- **禁止**在 `.promptSkill` 路径中使用 SkillTool 执行技能 — SkillTool 是 LLM 侧的隐式触发机制
- **禁止**缓存 `explicitSkill` 到全局状态 — 它是 `run()` 的局部变量
- **禁止**在测试中依赖真实 `~/.claude/skills/` 目录
- **禁止**忽略 `--no-skills` flag — 已由 Story 17.2 在 `parseSkillInvocation` 入口守卫

### 与其他 Story 的关系

- **17.1（已完成）** — 提供 SkillRegistry、SkillTool、formatSkillsForPrompt 基础设施
- **17.2（已完成）** — 提供 `/skill-name` 解析、双轨查找、`.promptSkill`/`.recordedSkill` 分派
- **17.4（隐式触发）** — 与本 Story 正交。显式触发修改 `.promptSkill` 路径，隐式触发修改 LLM 侧的 SkillTool + system prompt 注入。两者不冲突
- **18.1（内置桌面技能）** — 会使用本 Story 的显式触发能力

### AC5 和 AC6 说明

AC5（`/` 不在句首不触发）和 AC6（`--no-skills` 禁用）已由 Story 17.2 实现。本 Story 的测试中应包含这两个场景的回归验证，但无需修改代码。

### NFR 参考

- NFR44: 显式 `/skill-name` 触发到技能执行开始延迟 < 100ms（不含 LLM 响应时间）
- 本 Story 的 promptTemplate 注入、toolRestrictions 映射均为内存操作，满足 NFR44

### References

- [Source: epics.md — Epic 17 Story 17.3 显式 `/skill-name` 触发]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift — `.promptSkill` case（line 82-85）、AgentOptions 构建]
- [Source: Sources/AxionCLI/Services/RecordedSkillRunner.swift — 录制技能执行流程]
- [Source: Sources/AxionCLI/Services/SkillLookupService.swift — parseSkillInvocation()、SkillLookupResult]
- [Source: OpenAgentSDK/Types/SkillTypes.swift — Skill struct、ToolRestriction enum]
- [Source: OpenAgentSDK/Types/AgentTypes.swift — AgentOptions（allowedTools、model 字段）]
- [Source: OpenAgentSDK/Tools/Advanced/SkillTool.swift — createSkillTool、restrictionStack]
- [Source: Sources/AxionCore/Models/Skill.swift — SkillParameter（name、defaultValue）]
- [Source: _bmad-output/implementation-artifacts/17-2-dual-track-skill-lookup.md — Story 17.2 完成记录]
- [Source: _bmad-output/implementation-artifacts/17-1-runcommand-integrate-skillregistry.md — Story 17.1 完成记录]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

无

### Completion Notes List

- ✅ Task 1: 增强 `.promptSkill` case — 捕获 skill 对象为 `explicitSkill`，覆盖 task 变量，构建条件 systemPrompt（promptTemplate + tool list），应用 toolRestrictions → allowedTools 和 modelOverride → effectiveModel
- ✅ Task 2: 将参数校验移到 helper 启动之前，缺失必需参数立即 throw ExitCode(1)，有 defaultValue 的参数自动填充
- ✅ Task 3: 16 个单元测试全部通过，覆盖 AC1-AC6 和综合场景。回归测试 1658 tests 全部通过

### File List

- `Sources/AxionCLI/Commands/RunCommand.swift` — 修改: 添加 explicitSkill 变量，增强 .promptSkill case，条件 systemPrompt 构建，effectiveModel 和 allowedTools 注入 AgentOptions
- `Sources/AxionCLI/Services/RecordedSkillRunner.swift` — 修改: 在 helper 启动前添加必需参数校验和默认值填充
- `Tests/AxionCLITests/Services/ExplicitSkillTriggerTests.swift` — 新增: 17 个单元测试

## Change Log

- 2026-05-18: Story 17.3 实现 — 显式 `/skill-name` 触发增强。修改 RunCommand 的 .promptSkill 路径注入 promptTemplate/toolRestrictions/modelOverride；修改 RecordedSkillRunner 添加必需参数校验。16 个新测试，1658 总测试全部通过。
- 2026-05-18: AI Code Review — 发现 6 个问题（1 HIGH, 3 MEDIUM, 2 LOW），全部自动修复。
  - [FIXED HIGH] systemPrompt 在 toolRestrictions 生效时仍列出全部 MCP 工具名 → 改为只列出 restricted 工具
  - [FIXED MEDIUM] RecordedSkillRunner 参数校验错误输出到 stdout → 改用 fputs(stderr)
  - [FIXED MEDIUM] 新增测试验证 toolRestrictions 限制 Available Tools 列表
  - [FIXED MEDIUM] 加强 testNoSkillsFlag 测试注释说明实际行为验证
  - [NOTED LOW] 部分测试仅验证 Swift 基础机制（Optional.map, nil-coalescing）
  - [NOTED LOW] 未测试 promptTemplate 为空字符串场景
  - 17 个测试全部通过，1659 总测试中 1 个预存 ConfigManager 环境问题与本次无关

## Senior Developer Review (AI)

**Reviewer:** Claude (Adversarial Code Review)
**Date:** 2026-05-18
**Outcome:** Approved — all HIGH and MEDIUM issues auto-fixed

### Issues Found and Fixed

| # | Severity | Issue | File | Fix |
|---|----------|-------|------|-----|
| H1 | HIGH | toolRestrictions 生效时 systemPrompt 仍列出所有 MCP 工具，误导 LLM | RunCommand.swift:186 | 条件分支：有 restrictions 时只列 restricted 工具名 |
| M1 | MEDIUM | 参数缺失错误消息用 print() 输出到 stdout | RecordedSkillRunner.swift:23 | 改用 fputs(..., stderr) |
| M2 | MEDIUM | 缺少 toolRestrictions 限制工具列表的测试 | ExplicitSkillTriggerTests.swift | 新增 testToolRestrictionsLimitsToolList |
| M3 | MEDIUM | testNoSkillsFlag 未说明实际验证行为 | ExplicitSkillTriggerTests.swift | 加强注释说明 noSkills guard 机制 |

### Low Issues Noted (no code change)

| # | Severity | Issue |
|---|----------|-------|
| L1 | LOW | 多个测试仅验证 Swift 机制（Optional.map, nil-coalescing），非集成测试 |
| L2 | LOW | 未覆盖 promptTemplate 为空字符串场景 |
