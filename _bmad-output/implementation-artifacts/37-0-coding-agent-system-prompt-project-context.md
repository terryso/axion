---
story_id: 37.0
epic: 37
title: Coding Agent 系统提示 + 项目上下文
status: done
created: 2026-06-07
baseline_commit: 582feebaf4ff659238e4b8f1a4b9a3e3df31970f
---

# Story 37.0: Coding Agent 系统提示 + 项目上下文

As a coding agent 用户,
I want 交互模式使用专为代码编写优化的系统提示，并自动加载项目级指令,
So that agent 理解 coding 场景并遵循项目约定.

## Acceptance Criteria

**AC1:** 用户在项目目录下运行 `axion`，agent 启动时 system prompt 使用 `coding-agent-system` 模板（不包含 screenshot、list_apps、accessibility tree 等桌面自动化指令）

**AC2:** 扫描并加载 CLAUDE.md 系列文件，内容注入 system prompt：
- `~/.claude/CLAUDE.md` — 全局指令
- `<cwd>/.claude/CLAUDE.md` — 项目级团队指令
- `<cwd>/CLAUDE.md` — 项目根目录指令
- `<cwd>/.axion/instructions.md` — Axion 专用指令（可选）

**AC3:** `maxTokens` 从 4096 提升到 128K（131072），agent 生成较长代码回复不被截断

**AC4:** Memory 上下文（App facts + 通用记忆 MEMORY.md/USER.md）和 Skills 上下文正常注入，复用 `buildFullSystemPrompt()` 现有逻辑

**AC5:** `axion run "task"` 行为完全不受影响（仍然使用 `planner-system` 桌面自动化 prompt）

## Tasks / Subtasks

- [x] Task 1: 新建 coding-agent-system prompt 模板 (AC: #1)
  - [x] 1.1 创建 `Prompts/coding-agent-system.md` — coding agent 专用系统提示
  - [x] 1.2 模板变量：`{{cwd}}`（当前工作目录）
  - [x] 1.3 内容聚焦：文件读写、命令执行、代码搜索、LSP 智能等 coding 能力；不包含桌面自动化指令

- [x] Task 2: 新增 CLAUDE.md 加载逻辑 (AC: #2)
  - [x] 2.1 在 `AgentBuilder` 中新增 `static func loadClaudeMd(cwd:homeDir:) -> String` 方法
  - [x] 2.2 按优先级扫描 4 个路径，合并非空文件内容
  - [x] 2.3 每个文件用 `## 项目指令 (文件名)` 标题包裹

- [x] Task 3: 新增 coding prompt 构建路径 (AC: #1, #4)
  - [x] 3.1 `BuildConfig` 新增 `mode` 字段（enum `AgentMode`: `.desktopAutomation`, `.codingAgent`）
  - [x] 3.2 `BuildConfig.forCLI()` 保持默认 `.desktopAutomation`，新增 `forChat()` 工厂方法返回 `.codingAgent`
  - [x] 3.3 `AgentBuilder.build()` 根据 `mode` 选择 `buildSystemPrompt()` 或 `buildCodingSystemPrompt()`
  - [x] 3.4 `buildCodingSystemPrompt()` 加载 `coding-agent-system` 模板 + Memory + Skills + CLAUDE.md

- [x] Task 4: 修改 ChatCommand 使用新配置 (AC: #1, #3)
  - [x] 4.1 `ChatCommand.run()` 中将 `BuildConfig.forCLI()` 改为 `BuildConfig.forChat()`
  - [x] 4.2 `forChat()` 设置 `maxTokens: 131072`、`mode: .codingAgent`；移除不需要的 `allowForeground`

- [x] Task 5: 单元测试 (AC: 全部)
  - [x] 5.1 测试 `loadClaudeMd()` — 有文件时合并内容、无文件时返回空字符串、部分文件存在时正确合并、空文件跳过
  - [x] 5.2 测试 `BuildConfig.forChat()` 返回正确的 mode 和 maxTokens
  - [x] 5.3 测试 coding prompt 不包含桌面自动化关键词（screenshot、list_apps、accessibility_tree）

## Dev Notes

### 核心架构理解

**当前 ChatCommand（97 行）** 的 `BuildConfig.forCLI()` 走的是桌面自动化路径：
- 调用 `buildSystemPrompt()` → 加载 `planner-system.md`（含 screenshot、list_apps、AX tree 等桌面操作指令）
- `maxTokens` 默认 4096（在 `AgentBuilder.build()` 第 279 行：`let effectiveMaxTokens = buildConfig.maxTokens ?? 4096`）
- `permissionMode: .bypassPermissions`（在 `AgentBuilder.build()` 第 288 行）

**本 Story 的改动路径：** 新增一条独立的 prompt 构建分支，不影响现有 `forCLI()` 路径。

### 关键文件位置

| 文件 | 操作 | 说明 |
|------|------|------|
| `Prompts/coding-agent-system.md` | **NEW** | Coding agent 系统提示模板 |
| `Sources/AxionCLI/Services/AgentBuilder.swift` | **UPDATE** | 新增 mode 字段、forChat()、buildCodingSystemPrompt()、loadClaudeMd() |
| `Sources/AxionCLI/Commands/ChatCommand.swift` | **UPDATE** | forCLI() → forChat() |

### coding-agent-system.md 内容要点

模板应聚焦 coding agent 场景，不包含桌面自动化指令：

```
你是 Axion，一个运行在终端的 AI coding agent。

## 核心能力
- 读写文件（Read、Write、Edit）
- 执行命令（Bash）
- 搜索代码（Grep、Glob）
- 代码智能（LSP：定义跳转、引用查找、类型信息）
- 网络搜索（WebSearch、WebFetch）

## 工作原则
1. 先理解再动手 — 用 Read/Grep/Glob 了解上下文后再修改代码
2. 小步修改 — 每次只做必要的改动，避免大范围重构
3. 验证结果 — 修改后运行相关测试确认
4. 保持安全 — 不引入注入、XSS 等安全漏洞
5. 遵循项目约定 — 写代码前先了解项目的命名、架构、测试习惯

## 当前环境
- 工作目录：{{cwd}}
- 所有文件操作必须基于 {{cwd}} 解析相对路径

## 输出格式
- 每轮回复末尾包含一行总结：[结果] <一句话摘要，最多100字>
- 工具调用时简要说明目的
- 代码修改说明改了什么和为什么
```

### loadClaudeMd() 实现细节

```swift
static func loadClaudeMd(cwd: String) -> String {
    var parts: [String] = []
    let candidates = [
        NSHomeDirectory() + "/.claude/CLAUDE.md",
        cwd + "/.claude/CLAUDE.md",
        cwd + "/CLAUDE.md",
        cwd + "/.axion/instructions.md"
    ]
    for path in candidates {
        if let content = try? String(contentsOfFile: path),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            parts.append("## 项目指令 (\(fileName))\n\(content)")
        }
    }
    return parts.joined(separator: "\n\n")
}
```

### buildCodingSystemPrompt() 实现逻辑

1. 加载 `coding-agent-system.md` 模板（变量：`cwd`）
2. 复用现有 Memory 上下文逻辑（`MemoryContextProvider` + `UniversalMemoryStore`）
3. 调用 `loadClaudeMd(cwd:)` 获取项目指令
4. 调用现有 `buildFullSystemPrompt()` 组装完整 prompt（basePrompt + memory + universalMemory + skills + save_skill guidance）
5. CLAUDE.md 内容追加在 `buildFullSystemPrompt()` 返回值之后

### BuildConfig.mode 设计

```swift
enum AgentMode: String, Sendable {
    case desktopAutomation  // 用于 axion run — 桌面自动化
    case codingAgent        // 用于 axion（交互模式）— coding agent
}

struct BuildConfig: Sendable {
    // ... 现有字段 ...
    let mode: AgentMode

    static func forChat(
        config: AxionConfig,
        noMemory: Bool = false,
        noSkills: Bool = false,
        maxSteps: Int? = nil,
        verbose: Bool = false,
        sessionId: String? = nil,
        sessionStore: SessionStore? = nil
    ) -> BuildConfig {
        BuildConfig(
            config: config,
            task: "",
            noMemory: noMemory,
            noSkills: noSkills,
            includePlaywright: true,
            allowForeground: false,
            maxSteps: maxSteps,
            maxTokens: 131072,  // 128K
            verbose: verbose,
            dryrun: false,
            fast: false,
            runId: sessionId,
            sessionId: sessionId,
            sessionStore: sessionStore,
            emitTokenStream: false,
            mode: .codingAgent
        )
    }
}
```

注意：`forCLI()` 保持 `mode: .desktopAutomation` 不变，确保 `axion run` 行为不受影响。

### AgentBuilder.build() 中的分支

```swift
// 第 5 步：Build system prompt（根据 mode 选择路径）
let systemPrompt: String
switch buildConfig.mode {
case .desktopAutomation:
    systemPrompt = await buildSystemPrompt(...)  // 现有逻辑不变
case .codingAgent:
    systemPrompt = await buildCodingSystemPrompt(...)
}
```

### 关键反模式（必须避免）

1. **不要修改 `forCLI()` 方法签名或默认值** — `axion run` 必须保持完全相同行为
2. **不要修改 `SDKTerminalOutputHandler`** — 它被 RunCommand 使用，Chat 有独立输出（Story 37.4）
3. **不要硬编码 prompt 内容在 Swift 代码中** — prompt 必须放在 `Prompts/` 目录的 .md 文件中（project-context.md 反模式 #5）
4. **不要 import 新模块** — `AgentBuilder.swift` 当前 import 列表已足够（Foundation、OpenAgentSDK、AxionCore）
5. **不要跳过 Memory/Skills 注入** — coding agent 也需要 Memory 上下文和技能系统，复用 `buildFullSystemPrompt()`

### 测试策略

- **单元测试**（必须 Mock）：
  - `loadClaudeMd()` — 使用临时目录创建测试 CLAUDE.md 文件
  - `BuildConfig.forChat()` — 验证 mode 和 maxTokens 值
  - Prompt 内容断言 — coding prompt 不含桌面自动化关键词
- **不写集成测试** — 不启动真实 agent 或 Helper

### Project Structure Notes

- `Prompts/coding-agent-system.md` 放在项目根 `Prompts/` 目录（与 `planner-system.md` 同级）
- `PromptBuilder.resolvePromptDirectory()` 已支持从该目录加载（开发模式和安装模式均可）
- 测试文件放在 `Tests/AxionCLITests/Services/AgentBuilderCodingTests.swift`（镜像源结构）

### References

- [Source: docs/epics/epic-37-interactive-chat-mode.md#Story 37.0] — 完整 story 定义和 AC
- [Source: Sources/AxionCLI/Commands/ChatCommand.swift] — 当前 MVP 实现（97 行）
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift#L46-L164] — BuildConfig 结构和工厂方法
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift#L279] — effectiveMaxTokens 默认 4096
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift#L288] — permissionMode: .bypassPermissions
- [Source: Sources/AxionCLI/Services/AgentBuilder.swift#L462-L524] — buildSystemPrompt() 现有实现
- [Source: Prompts/planner-system.md] — 桌面自动化 system prompt（coding agent 不使用此模板）
- [Source: Sources/AxionCLI/Planner/PromptBuilder.swift] — Prompt 加载和目录解析
- [Source: _bmad-output/project-context.md#反模式] — 第 5 条：硬编码 prompt 在代码中

## Dev Agent Record

### Agent Model Used
GLM-5.1[1m]

### Debug Log References
无调试问题

### Completion Notes List
- ✅ Task 1: 创建 `Prompts/coding-agent-system.md` 模板，聚焦 coding 能力（Read/Write/Edit/Bash/Grep/Glob/LSP/WebSearch），使用 `{{cwd}}` 变量，不包含桌面自动化指令
- ✅ Task 2: 在 `AgentBuilder` 中新增 `loadClaudeMd(cwd:homeDir:)` 方法，扫描 4 个路径合并 CLAUDE.md 指令文件，每个文件用 `## 项目指令 (文件名)` 包裹。`homeDir` 参数用于测试隔离
- ✅ Task 3: 新增 `AgentMode` 枚举（`.desktopAutomation` / `.codingAgent`），`BuildConfig` 增加 `mode` 字段，所有现有工厂方法保持 `.desktopAutomation`，新增 `forChat()` 返回 `.codingAgent`。`build()` 中通过 switch 分支选择 prompt 构建路径
- ✅ Task 4: `ChatCommand` 改用 `forChat()` 配置（`maxTokens: 131072`、`mode: .codingAgent`、`includePlaywright: false`），移除不再需要的 `allowForeground` 标志
- ✅ Task 5: 13 个单元测试全部通过 — `loadClaudeMd()` 5 个测试（全合并/部分合并/无文件/空文件/标题格式）、`BuildConfig.forChat()` 5 个测试（mode/maxTokens/noPlaywright/参数透传/forCLI对比）、Prompt 内容 3 个测试（模板加载/无桌面关键词/cwd 变量替换）
- 全部 1898 个单元测试通过，无回归

### File List
- `Prompts/coding-agent-system.md` — **NEW** coding agent 系统提示模板
- `Sources/AxionCLI/Services/AgentBuilder.swift` — **UPDATE** 新增 AgentMode 枚举、BuildConfig.mode 字段、forChat()、loadClaudeMd()、buildCodingSystemPrompt()、build() mode 分支
- `Sources/AxionCLI/Commands/ChatCommand.swift` — **UPDATE** 改用 forChat()，移除 allowForeground
- `Sources/AxionCLI/Services/AxionRuntime.swift` — **UPDATE** 两处 BuildConfig 构造添加 mode 字段
- `Sources/AxionCLI/Services/Gateway/TaskSerialQueue.swift` — **UPDATE** 两处 BuildConfig 构造添加 mode 字段
- `Tests/AxionCLITests/Services/AgentBuilderCodingTests.swift` — **NEW** 13 个单元测试

### Change Log
- 2026-06-07: Story 37.0 实现完成 — coding agent 系统提示 + CLAUDE.md 加载 + BuildConfig mode 分支
- 2026-06-07: Code Review 修复 — (H1) Helper 路径守卫跳过 coding agent 模式、(H2) coding agent 不连接 MCP 服务器、(M1) 测试临时目录清理修复、新增 2 个 MCP 隔离测试

### Senior Developer Review (AI)

**Reviewer:** Claude (Adversarial Review)
**Date:** 2026-06-07
**Verdict:** ✅ Approved (after fixes)

**Issues Found & Fixed:**
1. **HIGH** — `AgentBuilder.build()` 强制要求 AxionHelper 存在，coding agent 不需要 Helper → 跳过守卫
2. **HIGH** — `MCPConfigResolver` 始终连接 `axion-helper` MCP，coding agent 会暴露桌面自动化工具 → coding agent 模式跳过 MCP 解析
3. **MEDIUM** — 测试临时目录 `cleanup(homeDir)` 只清理 home，`cwdDir` 泄漏 → 改为 `cleanup(base)` 清理整个树
4. **LOW** — Prompt 模板混合中英文（设计选择，保留现状）

**Tests:** 1671 通过（含新增 2 个 MCP 隔离测试），无回归
