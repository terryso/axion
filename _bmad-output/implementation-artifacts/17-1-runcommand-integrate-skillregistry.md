# Story 17.1: RunCommand 集成 SkillRegistry

Status: done

## Story

As a 用户,
I want Axion 启动时自动发现并加载 `~/.claude/skills/` 和 `~/.agents/skills/` 下的技能,
So that 我不需要手动配置就能使用已有的技能生态.

## Acceptance Criteria

1. **AC1: 自动技能发现与注册**
   - **Given** `~/.claude/skills/polyv-live-cli/SKILL.md` 存在
   - **When** 用户运行 `axion run "任意任务"`
   - **Then** RunCommand 创建 Agent 前，调用 `SkillLoader.discoverSkills()` 扫描默认目录，将发现的技能注册到 `SkillRegistry`

2. **AC2: SkillTool 注册到 Agent**
   - **Given** `SkillRegistry` 中有已注册技能
   - **When** Agent 创建完成
   - **Then** `createSkillTool(registry:)` 作为工具注册到 Agent 的工具池，LLM 可通过 Skill 工具发现和调用技能

3. **AC3: 同名技能 last-wins 去重**
   - **Given** 多个目录下有同名技能（如 `~/.claude/skills/foo/` 和 `~/.agents/skills/foo/`）
   - **When** 加载完成
   - **Then** 按目录优先级 last-wins 去重（SDK `SkillLoader.discoverSkills()` 已实现此逻辑）

4. **AC4: 空技能目录不影响运行**
   - **Given** 扫描目录中没有 SKILL.md 文件
   - **When** 启动 Agent
   - **Then** SkillRegistry 为空，SkillTool 仍注册但不可用，不影响正常任务执行

5. **AC5: 技能描述注入 system prompt**
   - **Given** SkillRegistry 中有用户可调用且可用的技能
   - **When** 构建 system prompt
   - **Then** `formatSkillsForPrompt()` 输出追加到 system prompt 末尾，LLM 可发现技能

6. **AC6: `--no-skills` 禁用技能**
   - **Given** 用户运行 `axion run --no-skills "任务"`
   - **When** 启动 Agent
   - **Then** 不扫描技能目录，不注册 SkillTool，不注入技能描述到 system prompt

## Tasks / Subtasks

- [x] Task 1: 添加 `--no-skills` CLI 参数 (AC: #6)
  - [x] 1.1 在 `RunCommand` 添加 `@Flag(name: .long, help: "禁用技能系统") var noSkills: Bool = false`

- [x] Task 2: 技能发现与注册 (AC: #1, #3, #4)
  - [x] 2.1 在 RunCommand.run() 中，config 加载后、system prompt 构建前，创建 `SkillRegistry`
  - [x] 2.2 调用 `registry.registerDiscoveredSkills()` 使用 SDK 默认目录（`~/.config/agents/skills`、`~/.agents/skills`、`~/.claude/skills`、`$PWD/.agents/skills`、`$PWD/.claude/skills`）
  - [x] 2.3 当 `--no-skills` 时跳过技能扫描

- [x] Task 3: SkillTool 注册到 Agent (AC: #2, #4, #6)
  - [x] 3.1 在 `AgentOptions.tools` 数组中添加 `createSkillTool(registry: registry)`（当技能系统启用时）
  - [x] 3.2 当 `--no-skills` 时不添加 SkillTool；registry 为空时仍注册（SkillTool 不可用但不影响运行，见 AC4）

- [x] Task 4: 技能描述注入 system prompt (AC: #5, #6)
  - [x] 4.1 在 `buildFullSystemPrompt()` 方法中，追加 skills prompt 参数
  - [x] 4.2 当 registry 有用户可调用技能时，调用 `registry.formatSkillsForPrompt()` 获取描述文本
  - [x] 4.3 以 "\n\n## Available Skills\n" section header 追加到 prompt 末尾
  - [x] 4.4 当 `--no-skills` 或 registry 为空时不注入

- [x] Task 5: 单元测试 (All ACs)
  - [x] 5.1 新建 `Tests/AxionCLITests/Commands/SkillIntegrationTests.swift`
  - [x] 5.2 测试 SkillLoader 从临时目录加载技能 → registry 注册成功
  - [x] 5.3 测试 SkillTool 创建不崩溃（registry 为空和非空两种情况）
  - [x] 5.4 测试 formatSkillsForPrompt 输出包含已注册技能描述
  - [x] 5.5 测试 --no-skills 模式下不扫描、不注册、不注入
  - [x] 5.6 测试同名技能 last-wins 去重（使用 SDK 默认行为验证）
  - [x] 5.7 测试空目录不影响正常 agent 创建流程

## Dev Notes

### 核心设计：RunCommand 集成 SkillRegistry

本 Story 在 RunCommand 的 Agent 创建管线中集成 SDK 的 Skill 系统，使 Axion 能自动发现 `~/.claude/skills/` 等目录下的 SKILL.md 技能文件，并让 LLM 通过 SkillTool 调用技能。

**SDK API 表面（已存在，直接使用）：**

| SDK 组件 | 路径 | 用途 |
|---------|------|------|
| `SkillLoader.discoverSkills(from:skillNames:)` | `Skills/SkillLoader.swift` | 扫描目录加载 SKILL.md → `[Skill]` |
| `SkillRegistry` | `Tools/SkillRegistry.swift` | 线程安全技能注册表，DispatchQueue 保护 |
| `createSkillTool(registry:)` | `Tools/Advanced/SkillTool.swift` | 创建 Skill 工具供 LLM 调用 |
| `Skill` struct | `Types/SkillTypes.swift` | 技能定义：name, description, promptTemplate, whenToUse, toolRestrictions 等 |
| `SkillRegistry.registerDiscoveredSkills(from:skillNames:)` | `Tools/SkillRegistry.swift` | 一步完成发现+注册，返回注册数量 |
| `SkillRegistry.formatSkillsForPrompt()` | `Tools/SkillRegistry.swift` | 格式化技能列表注入 system prompt（500 token 预算） |

### RunCommand 管线集成点

当前 RunCommand.run() 流程：
```
1. ConfigManager.loadConfig()
2. Resolve API key
3. Resolve Helper path
4. Create MemoryStore
5. Load system prompt from planner-system.md  ← 在此之后注入 skills prompt
6. Configure MCP servers
7. Build safety hook registry
8. Build AgentOptions (tools: [createPauseForHumanTool()])  ← 在此添加 createSkillTool
8. Create Agent
9-10. Output handler + TakeoverIO
```

**集成位置（按步骤编号）：**

在步骤 5 之后（加载 base system prompt 之后），插入技能发现逻辑：
```swift
// 5b. Discover and register skills (Story 17.1)
let skillRegistry = SkillRegistry()
if !noSkills {
    let registeredCount = skillRegistry.registerDiscoveredSkills()
    if registeredCount > 0 {
        fputs("[axion] 已加载 \(registeredCount) 个技能\n", stderr)
    }
}
```

在步骤 8 构建 AgentOptions 时，添加 SkillTool：
```swift
var tools: [ToolProtocol] = [createPauseForHumanTool()]
if !noSkills {
    tools.append(createSkillTool(registry: skillRegistry))
}
```

在 buildFullSystemPrompt 中，追加技能描述：
```swift
// After memory context injection
let skillsPrompt = noSkills ? "" : skillRegistry.formatSkillsForPrompt()
if !skillsPrompt.isEmpty {
    prompt += "\n\n## Available Skills\n\n\(skillsPrompt)"
}
```

### SDK 默认技能目录（已实现，无需配置）

`SkillLoader.defaultSkillDirectories()` 按优先级（last-wins）：
1. `~/.config/agents/skills` — 最低优先级
2. `~/.agents/skills`
3. `~/.claude/skills` — Claude Code 技能目录
4. `$PWD/.agents/skills` — 项目级
5. `$PWD/.claude/skills` — 最高优先级（项目级 Claude Code 技能）

Axion 无需自定义目录，直接使用 SDK 默认值。当前 `~/.claude/skills/` 下已有 `polyv-live-cli`、`peekaboo-cli`、`browser-use` 等技能。

### SKILL.md 格式示例

```yaml
---
name: polyv-live-cli
description: 管理保利威直播服务
allowed-tools: Bash(npx polyv-live-cli@latest:*)
---

# 技能 prompt body（作为 promptTemplate）
...
```

Frontmatter 字段：`name`、`description`、`aliases`、`allowed-tools`、`model`、`when-to-use`、`argument-hint`

### 现有文件需要修改

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Sources/AxionCLI/Commands/RunCommand.swift` | 修改 | 添加 `--no-skills` 参数，集成 SkillRegistry 发现+注册+SkillTool+prompt 注入 |

**仅修改 RunCommand.swift 一个文件**。SDK 已提供所有基础设施（SkillLoader、SkillRegistry、SkillTool、formatSkillsForPrompt）。

### 新增文件

| 文件 | 说明 |
|------|------|
| `Tests/AxionCLITests/Commands/SkillIntegrationTests.swift` | 技能集成单元测试 |

### 项目结构

```
Sources/AxionCLI/Commands/
├── RunCommand.swift                    # 修改：添加 SkillRegistry 集成

Tests/AxionCLITests/Commands/
└── SkillIntegrationTests.swift         # 新增：技能集成测试
```

### 测试策略

- Swift Testing 框架（`import Testing`, `@Suite`, `@Test`, `#expect`）
- 测试使用临时目录创建 SKILL.md 文件，不依赖真实 `~/.claude/skills/`
- SkillLoader 可通过 `discoverSkills(from: [tempDir])` 指定目录
- SkillRegistry 可直接 `register()` 测试用 Skill
- 测试验证：
  - SkillLoader 从指定目录加载 → registry.find() 命中
  - createSkillTool 不崩溃（空/非空 registry）
  - formatSkillsForPrompt 输出包含技能名和描述
  - last-wins 去重（两个目录同 name，后者覆盖前者）
  - 空目录 → registry 为空 → 无 SkillTool → 正常运行

### 关键设计决策

- **SkillRegistry 作为 RunCommand.run() 的局部变量** — 每次运行创建新的 registry，不缓存跨运行（因为技能文件可能在运行间被用户修改）
- **技能发现失败不阻塞运行** — SkillLoader 内部使用 try? 容错，目录不存在时静默跳过
- **formatSkillsForPrompt 的 500 token 预算** — SDK 默认值，技能多时自动截断尾部，无需 Axion 自行控制
- **`--no-skills` 与 `--no-memory` 正交** — 两者独立控制，互不影响
- **不修改 buildFullSystemPrompt 签名中的 memoryContext 参数** — 新增 skillsPrompt 参数即可

### 反模式提醒

- **禁止**自行实现技能扫描逻辑 — 直接使用 `SkillRegistry.registerDiscoveredSkills()`
- **禁止**自行格式化技能列表 — 直接使用 `registry.formatSkillsForPrompt()`
- **禁止**创建新的 Skill 子类型或协议 — 使用 SDK 的 `Skill` struct
- **禁止**在测试中依赖真实 `~/.claude/skills/` 目录 — 使用临时目录
- **禁止**修改 SDK 代码 — SDK 功能已完备，Axion 只做集成
- **禁止**缓存 SkillRegistry 到全局状态 — 每次运行重新扫描
- **禁止**将技能发现结果写入日志或 trace（可能暴露用户技能列表为隐私信息）

### 与后续 Story 的关系

- **17.2（双轨查找）** — 需要本 Story 的 SkillRegistry 作为查找源，同时查找录制技能（`~/.axion/skills/*.json`）
- **17.3（显式触发）** — 需要本 Story 的 SkillRegistry + SkillTool，解析 `/skill-name` 语法
- **17.4（隐式触发）** — 依赖 formatSkillsForPrompt 注入 + SkillTool 自动匹配

### References

- [Source: epics.md — Epic 17 Story 17.1 RunCommand 集成 SkillRegistry]
- [Source: OpenAgentSDK Skills/SkillLoader.swift — discoverSkills()、defaultSkillDirectories()、loadSkillFromDirectory()]
- [Source: OpenAgentSDK Tools/SkillRegistry.swift — registerDiscoveredSkills()、formatSkillsForPrompt()、register()、find()]
- [Source: OpenAgentSDK Tools/Advanced/SkillTool.swift — createSkillTool(registry:)、SkillToolInput]
- [Source: OpenAgentSDK Types/SkillTypes.swift — Skill struct、ToolRestriction enum]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift — 当前 Agent 创建管线]
- [Source: _bmad-output/project-context.md — 技术栈（OpenAgentSDK 本地依赖）、模块边界、测试规则]
- [Source: ~/.claude/skills/polyv-live-cli/SKILL.md — 真实 SKILL.md 示例]

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

None.

### Completion Notes List

- Task 1: Added `@Flag(name: .long, help: "禁用技能系统") var noSkills: Bool = false` to RunCommand
- Task 2: Created `SkillRegistry` as local variable in `run()`, called `registerDiscoveredSkills()` after memory context but before system prompt build. Skipped when `--no-skills`.
- Task 3: Added `createSkillTool(registry:)` to `agentTools` array when `!noSkills`. Used local `var agentTools` instead of inline array literal in AgentOptions.
- Task 4: Extended `buildFullSystemPrompt` with `skillsPrompt` parameter. Appends `## Available Skills` section when non-empty. Pre-computed `skillsPrompt` via `formatSkillsForPrompt()` before calling `buildFullSystemPrompt`.
- Task 5: Created 14 tests covering all 6 ACs. All pass. Tests use temp directories for filesystem-based tests, no dependency on real `~/.claude/skills/`.

### File List

- `Sources/AxionCLI/Commands/RunCommand.swift` — Modified: added `--no-skills` flag, SkillRegistry creation, SkillTool registration, skills prompt injection
- `Tests/AxionCLITests/Commands/SkillIntegrationTests.swift` — New: 14 unit tests for skill integration
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — Modified: added 17-1 story entry with review status
- `_bmad-output/planning-artifacts/epics.md` — Modified: added Epic 17 stories
