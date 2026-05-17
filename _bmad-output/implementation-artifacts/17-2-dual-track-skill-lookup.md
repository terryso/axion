# Story 17.2: 双轨技能查找

Status: done

## Story

As a 用户,
I want `/xxx` 触发时 Axion 先查 prompt 技能（SKILL.md），再查录制技能（JSON）,
So that 两种技能类型共享统一的 `/xxx` 触发入口，我不需要关心技能的实现方式.

## Acceptance Criteria

1. **AC1: Prompt 技能优先命中**
   - **Given** `polyv-live-cli` 是 prompt 技能（SKILL.md），`open_calculator` 是录制技能（JSON）
   - **When** 用户输入 `/polyv-live-cli 获取频道列表`
   - **Then** 先查 SkillRegistry 命中 prompt 技能，走 Agent + promptTemplate 执行路径

2. **AC2: 录制技能回退命中**
   - **Given** 只有 `open_calculator` 存在于 `~/.axion/skills/`（JSON 录制技能），SkillRegistry 中无同名技能
   - **When** 用户输入 `/open_calculator`
   - **Then** 查 SkillRegistry 未命中，再查 `~/.axion/skills/*.json` 命中录制技能，走 SkillExecutor 回放路径

3. **AC3: 同名技能 prompt 优先**
   - **Given** 同名技能同时存在于 SkillRegistry 和 `~/.axion/skills/`
   - **When** 用户输入 `/xxx`
   - **Then** SkillRegistry 优先命中（prompt 技能优先），不查找录制技能

4. **AC4: 未命中降级为普通 prompt**
   - **Given** 用户输入 `/nonexistent-skill`
   - **When** 两轨均未命中
   - **Then** 整句作为普通 prompt 发送给 LLM 执行，不报错

5. **AC5: `--no-skills` 禁用双轨查找**
   - **Given** 用户运行 `axion run --no-skills "/skill-name task"`
   - **When** 启动 Agent
   - **Then** 不触发双轨查找，整句作为普通 prompt 发送给 LLM

6. **AC6: 录制技能执行后更新元数据**
   - **Given** 录制技能被双轨查找命中并执行成功
   - **When** 执行完成
   - **Then** 更新 skill JSON 文件的 `last_used_at` 和 `execution_count`（复用 SkillRunCommand 逻辑）

## Tasks / Subtasks

- [x] Task 1: 创建 `SkillLookupService` (AC: #1, #2, #3, #4)
  - [x] 1.1 在 `Sources/AxionCLI/Services/` 创建 `SkillLookupService.swift`
  - [x] 1.2 实现 `enum SkillLookupResult`：`.promptSkill(Skill)` / `.recordedSkill(AxionCore.Skill)` / `.notFound`
  - [x] 1.3 实现 `lookup(name:in:)` 方法：先查 `SkillRegistry.find(name)`，未命中则查 `~/.axion/skills/<name>.json`
  - [x] 1.4 使用 `SkillCompileCommand.skillsDirectory()` 获取录制技能目录
  - [x] 1.5 录制技能加载：`JSONDecoder` + `.iso8601` date strategy 解码 `AxionCore.Skill`

- [x] Task 2: 在 RunCommand 集成双轨查找 (AC: #1-#6)
  - [x] 2.1 在 RunCommand.run() 中，`task` 参数前缀匹配 `/` 时触发双轨查找
  - [x] 2.2 解析 `/skill-name` 提取技能名和剩余参数文本
  - [x] 2.3 `SkillLookupResult.promptSkill` → 正常 Agent 流程（SkillTool 已注册，LLM 会自动使用 promptTemplate）
  - [x] 2.4 `SkillLookupResult.recordedSkill` → 启动 Helper → 创建 SkillExecutor → 执行技能 → 输出结果
  - [x] 2.5 `SkillLookupResult.notFound` → 将原始 task 字符串传给 Agent 作为普通 prompt
  - [x] 2.6 `--no-skills` 时跳过双轨查找，直接走 Agent 流程

- [x] Task 3: 录制技能执行路径 (AC: #2, #6)
  - [x] 3.1 提取 `SkillRunCommand` 中的 Helper 启动、SkillExecutor 执行、元数据更新逻辑为可复用函数
  - [x] 3.2 在 RunCommand 中复用该函数执行录制技能
  - [x] 3.3 执行完成后更新 `last_used_at` 和 `execution_count`

- [x] Task 4: 单元测试 (All ACs)
  - [x] 4.1 新建 `Tests/AxionCLITests/Services/SkillLookupServiceTests.swift`
  - [x] 4.2 测试 SkillRegistry 命中返回 `.promptSkill`（AC1）
  - [x] 4.3 测试 SkillRegistry 未命中 + JSON 文件命中返回 `.recordedSkill`（AC2）
  - [x] 4.4 测试两者都有同名技能时返回 `.promptSkill`（AC3）
  - [x] 4.5 测试两者都未命中返回 `.notFound`（AC4）
  - [x] 4.6 测试 `--no-skills` 跳过查找（AC5）
  - [x] 4.7 测试录制技能执行后元数据更新（AC6）
  - [x] 4.8 测试边界情况：空技能名、特殊字符、无效 JSON 文件

## Dev Notes

### 核心设计：SkillLookupService

新建一个纯查找服务，不包含执行逻辑。执行逻辑留在 RunCommand 中根据查找结果分派。

```
SkillLookupService
  ├── lookup(name:) → SkillLookupResult
  │   ├── 1. registry.find(name) → .promptSkill(SDK Skill)
  │   ├── 2. load ~/.axion/skills/<name>.json → .recordedSkill(AxionCore Skill)
  │   └── 3. neither → .notFound
```

### 两种 Skill 类型对比

| 维度 | Prompt 技能 (SKILL.md) | 录制技能 (JSON) |
|------|----------------------|----------------|
| 来源 | OpenAgentSDK `SkillLoader` 扫描 | Axion `RecordingCompiler` 编译 |
| 存储位置 | `~/.claude/skills/<name>/SKILL.md` | `~/.axion/skills/<name>.json` |
| 类型 | `OpenAgentSDK.Skill` | `AxionCore.Skill` |
| 执行方式 | Agent + promptTemplate，LLM 驱动 | `SkillExecutor` MCP 回放，无 LLM |
| 注册位置 | `SkillRegistry` | 无注册表，按需从文件加载 |
| 查找 API | `registry.find(name)` | 直接读 JSON 文件 |

### SDK Skill（prompt 技能）vs AxionCore Skill（录制技能）

这两个是**完全不同的类型**，位于不同的模块：

- **`OpenAgentSDK.Skill`**：有 `name`, `description`, `aliases`, `promptTemplate`, `userInvocable`, `toolRestrictions`, `whenToUse` 等字段。通过 `SkillRegistry.find()` 查找。
- **`AxionCore.Skill`**：有 `name`, `description`, `version`, `parameters`, `steps`, `lastUsedAt`, `executionCount` 等字段。通过 `JSONDecoder` 从文件加载。

`SkillLookupResult` 需要用 enum 分别持有这两种类型。

### `/skill-name` 解析规则

在 RunCommand.run() 开头，检查 `task` 是否以 `/` 开头：
- 匹配模式：`/^\/(\S+)(?:\s+(.*))?$/`
- `/polyv-live-cli 获取频道列表` → name=`polyv-live-cli`, args=`获取频道列表`
- `/open_calculator` → name=`open_calculator`, args=nil
- `/` 单独一个斜杠 → 不触发，走普通 prompt
- 不以 `/` 开头的 task → 不触发双轨查找

### RunCommand 集成位置

在 `RunCommand.run()` 的步骤 1 之前（config 加载之前），插入双轨查找和分派逻辑：

```
0a. 解析 task 是否以 / 开头
0b. 如果是且 --no-skills 为 false：
    - 创建 SkillLookupService
    - 查找技能
    - .promptSkill → 继续正常 Agent 流程（SkillTool 已注册，LLM 会使用 promptTemplate）
    - .recordedSkill → 执行录制技能路径，提前 return
    - .notFound → 继续正常 Agent 流程（原始 task 传给 Agent）
0c. 如果不是或 --no-skills → 继续正常 Agent 流程
```

**关键点：`.promptSkill` 命中后仍走完整 Agent 流程**，因为 prompt 技能需要 LLM 来执行。SkillTool 已在 Story 17.1 注册，LLM 会通过 SkillTool 自动发现并使用技能的 promptTemplate。`.promptSkill` 命中时的唯一作用是确认技能存在，无需额外操作。

### 录制技能执行路径

当 `.recordedSkill` 命中时，不走 Agent 流程，而是直接回放：
1. 启动 Helper 进程（复用 `HelperProcessManager`）
2. 创建 `HelperMCPClientAdapter`
3. 创建 `SkillExecutor(client:)`
4. 解析参数（从 task 中 `/name` 后面的文本提取）
5. 执行 `executor.execute(skill:paramValues:)`
6. 更新 `last_used_at` 和 `execution_count`
7. 输出结果
8. 提前 return（不走 Agent 流程）

**复用 `HelperMCPClientAdapter`**：定义在 `SkillRunCommand.swift:109`，可提取到共享位置或直接 import 使用。

### 现有文件需要修改

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Sources/AxionCLI/Commands/RunCommand.swift` | 修改 | 在 run() 开头添加 `/skill-name` 解析和双轨查找分派逻辑 |
| `Sources/AxionCLI/Commands/SkillRunCommand.swift` | 修改 | 将 Helper 启动 + 执行 + 元数据更新逻辑提取为可复用函数 |

### 新增文件

| 文件 | 说明 |
|------|------|
| `Sources/AxionCLI/Services/SkillLookupService.swift` | 双轨技能查找服务 |
| `Tests/AxionCLITests/Services/SkillLookupServiceTests.swift` | 查找服务单元测试 |

### 项目结构

```
Sources/AxionCLI/
├── Commands/
│   ├── RunCommand.swift                 # 修改：添加 /skill-name 解析和双轨分派
│   └── SkillRunCommand.swift            # 修改：提取可复用执行函数
├── Services/
│   ├── SkillLookupService.swift         # 新增：双轨查找服务
│   └── SkillExecutor.swift              # 已有：录制技能执行器（不修改）

Tests/AxionCLITests/Services/
└── SkillLookupServiceTests.swift        # 新增：查找服务测试
```

### 测试策略

- Swift Testing 框架（`import Testing`, `@Suite`, `@Test`, `#expect`）
- SkillLookupService 测试：
  - 注入 mock SkillRegistry（或用真实 SkillRegistry + 手动注册）
  - 使用临时目录创建 JSON 录制技能文件
  - 测试三路查找优先级
- RunCommand 集成测试：
  - 测试 `/skill-name` 解析逻辑（正则匹配）
  - 测试 `--no-skills` 跳过查找

### 关键设计决策

- **SkillLookupService 是无状态 struct** — 每次 lookup 都从当前文件系统读取最新状态，不缓存
- **录制技能文件名即技能名** — `SkillCompileCommand` 保存时使用 `sanitizeFileName(name).json`，查找时用同样逻辑拼接路径
- **`/skill-name` 解析在 RunCommand 入口** — 不修改 Agent 或 SDK 层，保持关注点分离
- **`.promptSkill` 命中仍走 Agent 流程** — SkillTool 已注册，LLM 会自动使用 promptTemplate，无需额外操作
- **录制技能参数从 task 后缀提取** — `/skill-name key1=val1 key2=val2`，复用 `SkillRunCommand.parseParamStrings()` 逻辑

### 反模式提醒

- **禁止**修改 OpenAgentSDK 代码 — 双轨查找是 Axion 层逻辑
- **禁止**将 AxionCore.Skill 和 OpenAgentSDK.Skill 混用 — 它们是完全不同的类型
- **禁止**在 SkillLookupService 中执行技能 — 只负责查找，执行在 RunCommand 分派
- **禁止**缓存录制技能内容 — 每次查找从文件读取，用户可能在运行间修改
- **禁止**在测试中依赖真实 `~/.axion/skills/` 目录 — 使用临时目录
- **禁止**修改 SkillExecutor — 它已完备，只被调用
- **禁止**在 `.promptSkill` 路径中额外注入 prompt — SkillTool + formatSkillsForPrompt 已处理

### 与其他 Story 的关系

- **17.1（已完成）** — 提供 SkillRegistry 和 SkillTool 基础设施，本 Story 直接使用
- **17.3（显式触发）** — 在本 Story 的 `/skill-name` 解析基础上，增强为更完善的显式触发语法
- **17.4（隐式触发）** — 依赖 formatSkillsForPrompt 注入，LLM 自动匹配，与双轨查找独立

### 参数解析：从 task 字符串提取录制技能参数

录制技能的参数格式：`/skill-name key1=value1 key2=value2`

```
/open_calculator          → 无参数
/open_calculator app=Calc → paramValues = ["app": "Calc"]
/open_calculator url=http://example.com type=slow → paramValues = ["url": "http://example.com", "type": "slow"]
```

复用 `SkillRunCommand.parseParamStrings()` 进行 `key=value` 解析。如果 task 后缀不包含 `=`，整段文本作为无参数传入。

### References

- [Source: epics.md — Epic 17 Story 17.2 双轨技能查找]
- [Source: Sources/AxionCLI/Commands/RunCommand.swift — Agent 创建管线，步骤 5b SkillRegistry 集成]
- [Source: Sources/AxionCLI/Commands/SkillRunCommand.swift — 录制技能执行流程、HelperMCPClientAdapter、parseParamStrings()]
- [Source: Sources/AxionCLI/Commands/SkillCompileCommand.swift — skillsDirectory() 返回 ~/.axion/skills]
- [Source: Sources/AxionCLI/Services/SkillExecutor.swift — 录制技能 MCP 回放执行器]
- [Source: Sources/AxionCore/Models/Skill.swift — AxionCore.Skill 模型（录制技能 JSON）]
- [Source: OpenAgentSDK/Tools/SkillRegistry.swift — find()、has()、registerDiscoveredSkills()]
- [Source: OpenAgentSDK/Skills/SkillLoader.swift — discoverSkills()、defaultSkillDirectories()]
- [Source: _bmad-output/implementation-artifacts/17-1-runcommand-integrate-skillregistry.md — Story 17.1 完成记录]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.7 (GLM-5.1)

### Debug Log References

None.

### Completion Notes List

- Implemented `SkillLookupService` as a stateless struct with dual-track lookup: registry first, then recorded skill JSON files
- Created `RecordedSkillRunner` to extract reusable Helper startup + SkillExecutor execution + metadata update from `SkillRunCommand`
- Moved `HelperMCPClientAdapter` to shared location so both `SkillRunCommand` and `RecordedSkillRunner` can use it
- Integrated `/skill-name` parsing in `RunCommand.run()` at the top, before config loading
- `.promptSkill` hit continues to normal Agent flow (SkillTool already registered)
- `.recordedSkill` hit executes via `RecordedSkillRunner` and returns early
- `.notFound` continues to normal Agent flow with original task string
- `--no-skills` flag skips the entire dual-track lookup block
- 16 unit tests covering all 6 ACs plus edge cases (empty name, invalid JSON, special chars, URL-like params)
- All 1997 existing tests pass (2 pre-existing flaky tests: DoctorCommand API key check and HelperProcess NFR2 timing)

### File List

**New files:**
- Sources/AxionCLI/Services/SkillLookupService.swift
- Sources/AxionCLI/Services/RecordedSkillRunner.swift
- Sources/AxionCLI/Helper/HelperMCPClientAdapter.swift
- Tests/AxionCLITests/Services/SkillLookupServiceTests.swift

**Modified files:**
- Sources/AxionCLI/Commands/RunCommand.swift — Added `/skill-name` parsing and dual-track dispatch at run() entry
- Sources/AxionCLI/Commands/SkillRunCommand.swift — Refactored to use RecordedSkillRunner, removed inline HelperMCPClientAdapter

## Change Log

- 2026-05-18: Story 17.2 implemented — dual-track skill lookup with `/skill-name` trigger, prompt skill priority, recorded skill fallback, `--no-skills` bypass, and metadata update. 16 new tests, all passing.
- 2026-05-18: Senior Developer Review (AI) — 0 CRITICAL, 3 MEDIUM, 1 LOW found. Auto-fixed all: (1) RecordedSkillRunner helper leak on executor throw — moved to try/catch with guaranteed stop, (2) success message now prints before metadata update so it's not swallowed on write error, (3) eliminated duplicate SkillRegistry creation by hoisting to run() entry, (4) removed duplicate comment. All 16 tests pass after fixes.

## Senior Developer Review (AI)

**Reviewer:** Claude Opus 4.7 | **Date:** 2026-05-18 | **Outcome:** Approved (all issues auto-fixed)

### AC Validation

| AC | Status | Evidence |
|----|--------|----------|
| AC1 | PASS | `SkillLookupService.lookup()` checks `registry.find()` first → `.promptSkill` |
| AC2 | PASS | Falls through to JSON file load from `~/.axion/skills/` with `.iso8601` decoder |
| AC3 | PASS | Registry check returns immediately on hit, recorded track never reached |
| AC4 | PASS | `.notFound` case in RunCommand continues normal Agent flow |
| AC5 | PASS | `!noSkills` guard at RunCommand line 71 |
| AC6 | PASS | `RecordedSkillRunner` updates `lastUsedAt` + `executionCount` in skill JSON |

### Task Audit

All tasks marked [x] verified as implemented. File list matches git changes exactly.

### Issues Found & Fixed

1. **[MEDIUM] Helper leak on throw** — `RecordedSkillRunner` used `withTaskCancellationHandler` whose `onCancel` only fires on cancellation, not on `executor.execute()` throws. Fixed: replaced with explicit try/catch + guaranteed `helperManager.stop()`.
2. **[MEDIUM] Success message swallowed** — Print was after metadata write; if write threw, user saw nothing. Fixed: moved print before metadata update, wrapped update in do/catch with warning.
3. **[MEDIUM] Duplicate SkillRegistry** — `registerDiscoveredSkills()` called twice (line 73 + line 173). Fixed: hoisted registry creation to `run()` entry, reused for both lookup and Agent flow.
4. **[LOW] Duplicate comment** — Line 102-103 had identical `// 1. Load configuration` comment. Fixed in refactor.
