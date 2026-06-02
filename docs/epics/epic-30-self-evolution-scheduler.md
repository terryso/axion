---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
inputDocuments:
  - _bmad-output/planning-artifacts/prds/prd-axion-gateway-2026-05-29/prd.md
  - _bmad-output/planning-artifacts/architecture.md
project_name: 'axion'
user_name: 'Nick'
date: '2026-05-29'
status: 'complete'
epic: 30
title: '自进化调度'
---

# Epic 30: 自进化调度

Axion 在空闲时自动审查运行历史、提炼 memory、整理技能库。ReviewScheduler 在 run 后 fork 审查 agent（工具白名单隔离），CuratorScheduler 在空闲时触发 IntelligentCurator。用户不操作时 Axion 持续自我进化。

**FRs covered:** FR-3.1, FR-3.2, FR-3.3, FR-3.4, FR-3.5, FR-4.1, FR-4.2, FR-4.3, FR-4.4, FR-4.5, FR-4.6
**NFRs:** NFR-3
**新增文件:** ReviewScheduler.swift, CuratorScheduler.swift
**修改文件:** GatewayRunner.swift（集成调度器）, AgentBuilder.swift（buildReviewAgent）
**依赖:** Epic 28（可与 Epic 29 并行开发）

---

### Story 30.1: ReviewScheduler 与审查 Agent 隔离执行

As a Axion 用户,
I want Gateway 在任务完成后自动触发后台审查,
So that Axion 能从每次运行中提炼 memory 和 skill 更新.

**Acceptance Criteria:**

**Given** 一个 TG 任务刚刚完成
**When** ReviewScheduler 收到 AgentCompletedEvent
**And** ReviewScheduleConfig 判断满足审查间隔
**Then** 创建独立审查 agent（通过 AgentBuilder.buildReviewAgent()）
**And** 审查 agent 工具白名单仅包含 memory + skill 操作，无 MCP/Helper 连接
**And** 审查 agent 不与主任务共享 AxionRuntime 实例

**Given** ReviewScheduleConfig 判断不满足审查间隔
**When** ReviewScheduler 收到 AgentCompletedEvent
**Then** 记录 debug 日志 "审查间隔未满足，跳过"，不触发审查

**Given** 审查 agent 使用与主任务相同的模型（MVP）
**When** 审查执行完成
**Then** 审查遵循反模式清单：不捕获环境依赖失败、负面断言、一次性错误、一次性任务叙述

### Story 30.2: 审查结果处理与可选推送

As a Axion 用户,
I want 审查结果自动写入 memory 和 skill 系统，并可选择性推送到 TG,
So that 审查产出持久化且我能选择是否收到通知.

**Acceptance Criteria:**

**Given** 审查 agent 完成执行
**When** 审查产生 memory 更新
**Then** 结果写入 FactStore（通过 SDK FactStore API）

**Given** 审查 agent 完成执行
**When** 审查产生 skill 更新
**Then** 结果写入 SkillRegistry（更新对应 SKILL.md）

**Given** 审查 agent 完成执行
**When** 审查结果已处理
**Then** 审查事件记录到 trace（包含审查摘要和结果）

**Given** `gatewayNotifyCuratorResults` 配置为 true
**When** 审查完成
**Then** 审查摘要推送到 TG（如 "审查完成：更新 2 条 memory，修改 1 个技能"）

**Given** `gatewayNotifyCuratorResults` 配置为 false（默认）
**When** 审查完成
**Then** 不推送 TG 通知，仅记录 trace

### Story 30.3: CuratorScheduler 自动调度

As a Axion 用户,
I want Gateway 在空闲时自动触发 Curator 整理技能库,
So that 技能库持续保持整洁——合并重叠、修补过时、归档长期未用.

**Acceptance Criteria:**

**Given** 距上次任务完成已超过 `curatorIdleHours`（默认 2 小时）
**And** 距上次 Curator 运行已超过 `curatorIntervalHours`（默认 168 小时 = 7 天）
**When** CuratorScheduler 定时检查通过
**Then** 触发 IntelligentCurator.execute()
**And** Curator 内部使用 LLMSkillEvolver 更新 SKILL.md 内容

**Given** CuratorScheduler 触发 Curator
**When** Curator 扫描技能库
**Then** 仅操作 agent 创建的 SKILL.md，不触碰内置技能和用户置顶技能
**And** 可合并重叠技能、修补过时内容、归档 90 天未用技能
**And** 永不自动删除任何技能

**Given** Curator 运行完成
**When** 结果已处理
**Then** 运行结果持久化到 `.curator_state`（包含时间戳、操作摘要）
**And** `axion gateway status` 可查看上次 curator 时间

**Given** Curator 调度条件未满足（不满足空闲或间隔）
**When** CuratorScheduler 定时检查
**Then** 不触发 Curator，记录 debug 日志

**Given** 用户通过 CLI 执行 `axion curator run` 或 `axion curator run --dry-run`
**When** 命令运行
**Then** 行为不变（现有功能兼容），CuratorScheduler 不受影响

---

## 实现参考

### 复用组件

| 现有文件 | 复用方式 |
|---------|---------|
| `Sources/AxionCLI/Services/AgentBuilder.swift` | 新增 `buildReviewAgent()` 静态方法。复用现有 `build()` 的 apiKey/baseURL/model 解析逻辑，但工具集白名单化 |
| `Sources/AxionCLI/Services/Protocols/AgentBuilding.swift` | `AgentBuilding` protocol 需扩展 `buildReviewAgent()` 方法 |
| `Sources/AxionCLI/Runtime/Handlers/ReviewHandler.swift` | 当前是 stub——只检查 `shouldReview()` 后打日志，不执行审查。Epic 30 的 ReviewScheduler 替代其功能（在 Gateway 进程内执行完整审查） |
| `Sources/AxionCLI/Commands/CuratorCommand.swift` | `CuratorRunCommand` 展示了完整的 IntelligentCurator 构建和调用流程。CuratorScheduler 调用同样的 `IntelligentCurator.execute()`，区别在于自动触发而非 CLI 手动触发 |
| `Sources/AxionCLI/Services/AxionRuntime.swift` | `AxionRuntime` — ReviewScheduler 监听其 EventBus 发出的 `AgentCompletedEvent` |

### AgentBuilder.buildReviewAgent() 设计

```swift
// 在 AgentBuilder 中新增
static func buildReviewAgent(
    config: AxionConfig,
    eventBus: EventBus? = nil
) async throws -> Agent {
    // 1. 复用 apiKey/baseURL/model 解析（与 build() 相同）
    // 2. 工具白名单：仅 memory + skill 操作，无 MCP/Helper
    //    - 不包含 Bash, Skill, ToolSearch, AskUser
    //    - 不包含 MCP servers（mcpServers = nil）
    //    - 需确认 SDK 是否支持 AgentOptions.toolFilter 或类似机制
    //    - 备选方案：只传入白名单工具数组（参考 buildSkillAgent() 的模式）
    // 3. systemPrompt: 审查专用 prompt（包含反模式清单）
    // 4. 无 Hook, 无 Session, 无 Playwright
    // 5. 使用配置的 reviewModel（默认 claude-haiku-4-5）
}
```

**工具白名单隔离的关键点：**
- 当前 `AgentBuilder.buildSkillAgent()` 已实现类似模式：core tools only，排除 ToolSearch/AskUser
- `buildReviewAgent()` 更严格：只有 memory 读写 + skill 读写工具
- SDK 的 `AgentOptions.tools` 接受 `[ToolProtocol]` 数组，通过只传入白名单工具实现隔离
- 无需 `allowedTools` 过滤机制——直接控制传入的 tools 数组即可

### ReviewScheduler 执行流程

```
1. ReviewScheduler 监听 EventBus 的 AgentCompletedEvent
2. 检查 shouldReview()（间隔、消息数等）
3. 如果需要审查：
   a. 调用 AgentBuilder.buildReviewAgent() 创建独立 agent
   b. 构建 reviewPrompt（包含对话摘要 + 审查指令 + 反模式清单）
   c. reviewAgent.stream(reviewPrompt) 执行审查
   d. 结果写入 FactStore（memory 更新）
   e. 结果写入 SkillRegistry（skill 更新）
   f. 审查事件记录到 trace
   g. 如果 gatewayNotifyCuratorResults=true，推送 TG 通知
4. 审查 agent 不与主任务共享：
   - 独立 Agent 实例（不共享 AxionRuntime）
   - 不连接 Helper（无 MCP）
   - 不写入 EventBus（直接操作 FactStore/SkillRegistry）
```

### 审查反模式清单（参考 Hermes）

审查 agent 的 system prompt 必须包含以下禁止捕获的内容：
1. **环境依赖失败** — 如 "File not found: /Users/nick/..."，这是环境特定的，不应写入 memory
2. **负面断言** — 如 "此任务未能完成"，无学习价值
3. **一次性错误** — 如网络超时、API rate limit，不具有复现性
4. **一次性任务叙述** — 如 "用户让我打开计算器然后关闭"，过于具体

### CuratorScheduler 触发条件

```
两个条件同时满足时触发：
1. 空闲时间 > gatewayCuratorIdleHours（默认 2 小时）
   - 空闲定义：距上次 AgentCompletedEvent 的时间
   - GatewayRunner 维护 lastTaskCompletedAt 时间戳
2. 距上次 Curator 运行 > gatewayCuratorIntervalHours（默认 168 小时 = 7 天）
   - 读取 SkillCuratorStore.loadState().lastRunAt

定时检查频率：建议每 30 分钟检查一次（Timer 或 async 循环）
```

### Curator 安全边界（与 Hermes 一致）

- 仅操作 `agent_created` 来源的 SKILL.md
- 跳过 `bundled`（内置技能）
- 跳过 `hub_installed`（Hub 安装技能）
- 跳过 `pinned`（用户置顶技能）
- **永不自动删除任何技能**——只归档（修改 metadata 为 archived）

### CuratorScheduler 与 CuratorCommand 的关系

- `axion curator run` — CLI 手动触发，行为不变（CuratorCommand 已完整实现）
- `CuratorScheduler` — Gateway 进程内的自动调度器
- 两者调用同一个 `IntelligentCurator.execute()`，共享 `SkillCuratorStore` 状态
- 手动 `curator run` 会更新 `lastRunAt`，CuratorScheduler 下次检查时会看到这个时间戳

### .curator_state 持久化

Curator 运行结果持久化到现有 `SkillCuratorStore`（`~/.axion/skills/.curator_state`），包含：
- `lastRunAt: Date?`
- `runCount: Int`
- `lastRunSummary: String?`（操作摘要，如 "合并 2 个技能，归档 1 个技能"）

`axion gateway status` 需额外显示上次 Curator 运行时间，从 `SkillCuratorStore.loadState().lastRunAt` 读取。

### 文件位置

| 新增/修改文件 | 目录 | 说明 |
|-------------|------|------|
| `ReviewScheduler.swift` | `Sources/AxionCLI/Services/` | Actor — 监听 AgentCompletedEvent，触发隔离审查 |
| `CuratorScheduler.swift` | `Sources/AxionCLI/Services/` | Actor — 定时检查空闲+间隔，触发 IntelligentCurator |
| `AgentBuilder.swift` | `Sources/AxionCLI/Services/` | 新增 `buildReviewAgent()` 静态方法 |
| `AgentBuilding.swift` | `Sources/AxionCLI/Services/Protocols/` | Protocol 扩展 `buildReviewAgent()` |
| `GatewayRunner.swift` | `Sources/AxionCLI/Services/` | 集成 ReviewScheduler + CuratorScheduler（Epic 28 创建，Epic 30 补充调度器初始化） |
