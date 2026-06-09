# Axion Epic 37: 交互聊天模式

> **状态：待开发**
> **优先级：P0**
> **前置依赖：无（ChatCommand 已在 feat/interactive-chat 分支实现 MVP）**
> **技术验证：** 快速验证已完成，MVP 分支 `feat/interactive-chat`

## 背景与动机

Axion 的 `run` 命令是单次执行模式（`axion run "task"`），类似 `claude -p`。Epic 37 的目标是让 `axion` 无参数直接进入交互式多轮 REPL，成为类似 Claude Code 的 coding agent。

**MVP 已完成（feat/interactive-chat 分支）：**
- `ChatCommand.swift` — 交互 REPL，`axion` 无参数进入
- `agent.stream()` 每轮调用，流式输出
- `SessionStore` 会话持久化
- MCP 连接复用（SDK 0.7.6 修复）
- 工具验证通过：Read、Edit、Write、Bash、Glob、Grep

**MVP 的限制（本 Epic 要解决的）：**
- System Prompt 是桌面自动化的 `planner-system`（含 screenshot、list_apps），不适合 coding agent
- 无 CLAUDE.md / 项目级指令加载
- 输出是纯文本 `[axion]` 前缀格式，无 Markdown 渲染
- 只有 `/exit` 命令，缺少 `/help`、`/clear`、`/compact` 等
- 无权限审批，所有操作直接执行（当前 `permissionMode: .bypassPermissions`）
- `readLine()` 不支持多行输入和粘贴
- Ctrl+C 会杀死进程而非中断当前任务
- 中文输入 backspace 删除字符需要按两次
- `maxTokens=4096` 太小，coding agent 回复经常超限
- 无上下文用量提示，长对话可能 token 溢出
- 无会话恢复能力，退出后对话丢失
- 启动信息不足（缺模型、工作目录、session ID）

---

## 全局参数约定

本 Epic 所有 Story 共享以下默认参数，在 `ChatCommand` 的 `BuildConfig` 中生效：

| 参数 | 值 | 说明 |
|------|-----|------|
| 上下文窗口 | 200K tokens | 通过 `maxModelContextTokens` 配置 |
| 最大输出 token | 128K | 通过 `maxTokens` 配置（MVP 是 4096） |
| 自动压缩阈值 | SDK 内置（contextWindow - 13K buffer） | SDK `stream()` 自动 compact，通过 `compactBoundary` 系统事件通知（187K/200K 阈值） |
| PermissionMode | `canUseTool` 回调 + `.bypassPermissions` | 实际通过 `canUseTool` 回调控制权限（非 SDK `.default` 模式，因为 SDK `.default` 直接阻止非只读工具不等待用户确认） |
| System Prompt | coding-agent-system | 独立 prompt 模板，非桌面自动化的 planner-system |

---

### Story 37.0: Coding Agent 系统提示 + 项目上下文

As a coding agent 用户,
I want 交互模式使用专为代码编写优化的系统提示，并自动加载项目级指令,
So that agent 理解 coding 场景并遵循项目约定.

**当前问题：** `forCLI()` 使用 `buildSystemPrompt()` 加载 `planner-system` 模板（面向桌面自动化，含 screenshot、list_apps、accessibility tree 等指令）。交互模式需要自己的系统提示。

**实施：**

1. 新建 `Prompts/coding-agent-system.md` 系统提示模板，核心内容：

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

## 输出格式
- 每轮回复末尾包含一行总结：`[结果] <一句话摘要，最多100字>`
- 工具调用时简要说明目的
- 代码修改说明改了什么和为什么
```

2. 新建 `buildCodingSystemPrompt()` 方法（或在 `buildSystemPrompt` 中加 `mode` 参数）

```swift
// AgentBuilder.swift 新增
private static func buildCodingSystemPrompt(
    config: AxionConfig,
    cwd: String,
    memoryStore: FileBasedMemoryStore,
    memoryDir: String,
    skillRegistry: SkillRegistry,
    noMemory: Bool,
    noSkills: Bool
) async -> String {
    let promptDir = PromptBuilder.resolvePromptDirectory()
    let basePrompt = (try? PromptBuilder.load(
        name: "coding-agent-system",
        variables: ["cwd": cwd],
        fromDirectory: promptDir
    )) ?? ""

    // Memory context（复用现有逻辑）
    var memoryContext: String? = nil
    if !noMemory { ... }

    // CLAUDE.md 加载
    let claudeMdContext = loadClaudeMd(cwd: cwd)

    let skillsPrompt = noSkills ? "" : skillRegistry.formatSkillsForPrompt()
    return buildFullSystemPrompt(...)
}
```

3. **CLAUDE.md 加载** — 扫描以下路径，按优先级合并：
   - `~/.claude/CLAUDE.md` — 全局指令
   - `<project-root>/.claude/CLAUDE.md` — 项目级团队指令
   - `<project-root>/CLAUDE.md` — 项目根目录指令
   - `<project-root>/.axion/instructions.md` — Axion 专用指令

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
           !content.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("## 指令 (\(URL(fileURLWithPath: path).lastPathComponent))\n\(content)")
        }
    }
    return parts.joined(separator: "\n\n")
}
```

4. 在 `BuildConfig.forCLI()` 中根据 `mode` 参数选择不同的 prompt 构建路径
5. `maxTokens` 从 4096 改为 128K
6. `permissionMode` 从 `.bypassPermissions` 改为 `.default`

**新增文件：**
- `Resources/prompts/coding-agent-system.md`

**修改文件：**
- `Sources/AxionCLI/Services/AgentBuilder.swift` — 新增 `buildCodingSystemPrompt()`，`BuildConfig` 加 `mode` 字段

**Acceptance Criteria：**

**Given** 用户在 axion 项目目录下运行 `axion`
**When** agent 启动
**Then** system prompt 使用 `coding-agent-system` 模板（不包含 screenshot、list_apps 等桌面自动化指令）
**And** `CLAUDE.md` 内容被注入 system prompt

**Given** 项目根目录存在 `CLAUDE.md` 内容为 "所有测试用 Swift Testing 框架"
**When** agent 执行编码任务
**Then** agent 遵循该约定，生成 `@Test` 而非 `XCTestCase` 测试

**Given** `maxTokens` 设为 128K
**When** agent 生成较长的代码回复
**Then** 回复不会被截断（对比 MVP 中 maxTokens=4096 时的截断问题）

---

### Story 37.1: Slash 命令体系

As a CLI 用户,
I want 在交互模式中使用 /help、/clear、/compact 等斜杠命令,
So that 我可以控制对话行为而不用退出重进.

**Slash 命令清单：**

| 命令 | 功能 | 说明 |
|------|------|------|
| `/help` | 显示帮助 | 列出所有可用命令和快捷键 |
| `/clear` | 清屏 | 清除终端输出，不重置会话 |
| `/compact` | 压缩上下文 | 手动触发上下文压缩（SDK 已有 compact 机制） |
| `/model` | 显示/切换模型 | 无参数显示当前模型，带参数切换 |
| `/cost` | 显示用量 | 显示当前会话 token 用量和成本 |
| `/resume` | 恢复会话 | 无参数列出最近会话供选择，输入序号恢复（见 Story 37.8） |
| `/exit` `/quit` | 退出 | 已实现 |
| `/config` | 显示配置 | 显示当前生效的关键配置项 |

**实施：**

1. 新建 `Sources/AxionCLI/Chat/SlashCommand.swift`

```swift
enum SlashCommand {
    case help
    case clear
    case compact
    case model(String?)
    case cost
    case resume  // 无参数：列出会话供选择
    case config
    case exit

    static func parse(_ input: String) -> SlashCommand? {
        let parts = input.split(separator: " ", maxSplits: 1)
        let cmd = String(parts[0]).lowercased()
        let arg = parts.count > 1 ? String(parts[1]) : nil
        switch cmd {
        case "/help": return .help
        case "/clear": return .clear
        case "/compact": return .compact
        case "/model": return .model(arg)
        case "/cost": return .cost
        case "/sessions": return .sessions
        case "/resume": return .resume
        case "/config": return .config
        case "/exit", "/quit": return .exit
        default: return nil
        }
    }
}
```

2. 修改 `ChatCommand.swift` 的 REPL 循环，在 `agent.stream()` 之前检查 slash 命令

```swift
if let cmd = SlashCommand.parse(trimmed) {
    handleSlashCommand(cmd, buildResult: &buildResult)
    if case .exit = cmd { break }
    continue
}
```

3. `handleSlashCommand` 方法处理各命令

**Token 用量数据来源：**
- SDK 的 `SDKMessage.result` 包含 `numTurns`、`durationMs`
- LLM API response 中有 `usage.prompt_tokens` / `usage.completion_tokens`
- 需要在 ChatCommand 中维护一个 `TokenCounter`，从每次 stream 结束后的 result 事件中累计
- 如果 SDK 不暴露 token 计数，从 `SessionStore` 的 transcript 大小估算

**Acceptance Criteria：**

**Given** 用户在交互模式中输入 `/help`
**When** 命令执行
**Then** 显示所有可用 slash 命令列表

**Given** 用户输入 `/clear`
**When** 命令执行
**Then** 终端清屏，会话历史不变，下一轮对话仍记得上下文

**Given** 用户输入 `/model`
**When** 命令执行
**Then** 显示当前使用的模型名称

**Given** 用户输入 `/model gpt-4o`
**When** 命令执行
**Then** 切换模型并确认

**Given** 用户输入 `/cost`
**When** 命令执行
**Then** 显示当前会话累计 token 数和预估成本

---

### Story 37.2: Ctrl+C 优雅中断

As a CLI 用户,
I want 按 Ctrl+C 时只中断当前正在执行的任务而不是退出整个交互模式,
So that 我可以取消一个耗时操作但继续在同一会话中工作.

**实施：**

1. 注册 SIGINT 信号处理器，在 REPL 循环外捕获

```swift
import Darwin

var interrupted = false
let sigintSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
sigintSrc.setEventHandler { interrupted = true }
sigintSrc.resume()
```

2. 在 `ChatCommand` 中维护 `currentStreamTask: Task<Void, Never>?`
3. Ctrl+C 时 cancel 当前 Task，但保持 REPL 循环
4. 连续两次 Ctrl+C（2 秒内）退出程序

```swift
// REPL loop
while true {
    fputs("axion> ", stdout); fflush(stdout)
    guard let line = readLine(strippingNewline: true) else { break }
    // ...
    interrupted = false
    let streamTask = Task {
        for await message in buildResult.agent.stream(trimmed) {
            guard !Task.isCancelled else { return }
            outputHandler.handle(message)
        }
    }
    // 等待完成或中断
    await streamTask.value
}
```

**Acceptance Criteria：**

**Given** agent 正在执行一个耗时任务
**When** 用户按一次 Ctrl+C
**Then** 当前任务被中断，显示 `[axion] 已中断`，回到 `axion>` 提示符
**And** 会话历史保留，可以继续对话

**Given** 用户在 2 秒内连续按两次 Ctrl+C
**When** 第二次 Ctrl+C
**Then** 退出交互模式，显示 `[axion] 再见`

**Given** 用户在 `axion>` 提示符下按 Ctrl+C
**When** 没有任务在执行
**Then** 显示新行 `axion>`，不退出

---

### Story 37.3: 启动横幅 + 会话信息

As a CLI 用户,
I want 进入交互模式时看到有用的信息（模型、工作目录、session ID）,
So that 我知道当前环境和如何恢复会话.

**实施：**

1. 启动横幅（替换当前的 `[axion] 就绪 [157ms]`）：

```
╭──────────────────────────────────────╮
│ Axion v0.11.0                        │
│ Model: claude-sonnet-4-6             │
│ CWD: /Users/nick/CascadeProjects/axion │
│ Session: chat-a3f8b2c1               │
│ Context: 0/200K                      │
╰──────────────────────────────────────╯
```

2. 在 REPL 循环中，每次 stream 结束后更新上下文用量
3. `axion>` 提示符格式：`axion [3.2k/200k]> `
4. 退出时提示如何恢复：`[axion] 会话 chat-a3f8b2c1 已保存，使用 axion --resume chat-a3f8b2c1 恢复`

**修改文件：**
- `Sources/AxionCLI/Commands/ChatCommand.swift`

**Acceptance Criteria：**

**Given** 用户运行 `axion`
**When** 进入交互模式
**Then** 显示版本、模型、工作目录、session ID、上下文用量

**Given** 第一轮对话结束
**When** 下一轮 `axion>` 提示符出现
**Then** 提示符中显示当前上下文用量（如 `axion [3.2k/200k]> `）

**Given** 用户输入 `/exit`
**When** 退出
**Then** 显示 session ID 和恢复命令

---

### Story 37.4: 终端输出优化

As a CLI 用户,
I want 看到更清晰的输出格式——工具结果有摘要、LLM 回复有 Markdown 渲染、进度有动态指示,
So that 交互体验更接近 Claude Code 的水平.

**改进项：**

1. **工具调用格式优化** — 当前 `[axion] 执行: Bash` / `[axion] 结果: ...`
   改为缩进层级显示：
   ```
   ⏳ Bash: echo hello
   ✅ hello [120ms]
   ```

2. **LLM 回复直接输出** — 当前通过 `[axion]` 前缀包裹，改为直接在终端输出 LLM 文本，用空行分隔工具调用和回复

3. **进度指示** — LLM 等待时显示 spinner（`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`），工具执行时显示工具名 + spinner

4. **Markdown 简易渲染** — 对 LLM 回复中的 code block、bold、link 做基本终端渲染（ANSI 转义码）
   - `**bold**` → `\033[1mbold\033[0m`
   - `` `code` `` → `\033[36mcode\033[0m`
   - ```` ```code block``` ```` → 缩进 + 语法提示

**实施：**

1. 新建 `Sources/AxionCLI/Chat/ChatOutputFormatter.swift`
2. 新建 `Sources/AxionCLI/Chat/MarkdownTerminalRenderer.swift`
3. 修改 `ChatCommand.swift` 使用新的格式化器替代 `SDKTerminalOutputHandler`

**注意：** 不修改 `SDKTerminalOutputHandler`，它被 `RunCommand` 使用。Chat 模式有独立的输出格式化。

**Acceptance Criteria：**

**Given** agent 执行了一个 Bash 命令
**When** 结果返回
**Then** 显示工具名 + 状态图标 + 结果摘要 + 耗时

**Given** LLM 返回包含 `**bold**` 和 `` `code` `` 的文本
**When** 渲染到终端
**Then** bold 用粗体显示，code 用不同颜色显示

**Given** LLM 正在思考
**When** 等待时间 > 500ms
**Then** 显示动态 spinner

---

### Story 37.5: 权限审批机制

As a CLI 用户,
I want 在执行危险操作（文件覆盖、删除命令等）前收到确认提示,
So that 我可以防止意外破坏.

**实施：**

1. 将 `ChatCommand` 的 `permissionMode` 从 `.bypassPermissions` 改为 `.default`
2. 使用 SDK 已有的 `PermissionMode` 机制（`.default` 模式会触发 `permissionRequest` hook）
3. 在 `ChatCommand` 中注册 `permissionRequest` 事件处理

```swift
case .hookResponse(let data):
    if data.event == "permissionRequest" {
        // 显示操作详情，等待用户确认
        fputs("⚠️  即将执行: \(data.toolName) — \(data.description)\n", stderr)
        fputs("   允许？[y/n] ", stderr)
        fflush(stderr)
        if let answer = readLine(strippingNewline: true),
           answer.lowercased() == "y" {
            // approve
        }
    }
```

4. 支持三种模式（通过命令行 flag 选择）：
   - `--accept-edits` — 自动允许文件编辑，危险 Bash 仍需确认（对应 SDK `.acceptEdits`）
   - `--dangerously-skip-permissions` — 全部自动通过（当前 MVP 行为，对应 SDK `.bypassPermissions`）
   - 默认（不加 flag）— 写文件、危险 Bash 命令需确认（对应 SDK `.default`）

**危险操作判断规则（SDK 层面）：**
- Write/Edit：目标文件已存在 → 需确认
- Bash：命令含 `rm`、`drop`、`delete`、`truncate`、`force` → 需确认
- Read/Grep/Glob：无需确认

**Acceptance Criteria：**

**Given** 默认模式下 agent 要执行 `rm -rf /tmp/test`
**When** 权限请求触发
**Then** 终端显示确认提示，用户输入 `y` 后执行，`n` 后跳过

**Given** `--accept-edits` 模式下 agent 要写入已存在的文件
**When** 权限请求触发
**Then** 自动通过，无需确认

**Given** 默认模式下 agent 要执行 Read 工具
**When** 权限请求触发
**Then** 自动通过，无需确认

---

### Story 37.6: 多行输入支持

As a CLI 用户,
I want 能粘贴多行代码片段或用反斜杠续行,
So that 我可以输入复杂的 prompt 而不需要写成一行.

**实施：**

1. 检测 stdin 是否为 TTY（`isatty(STDIN_FILENO)`）
2. 在 TTY 模式下检测粘贴事件（bracket paste mode）

```swift
// 启用 bracket paste mode
 fputs("\u{1B}[?2004h", stderr)  // 开启
 // 退出时恢复
 fputs("\u{1B}[?2004l", stderr)  // 关闭
```

3. bracket paste 内容用 `\u{1B}[200~` 和 `\u{1B}[201~` 包裹，识别后合并为单条输入
4. 手动续行：行末 `\` + 回车 → 继续读取下一行，合并后发送

**Acceptance Criteria：**

**Given** 用户在 `axion>` 提示符下输入 `print(\` 然后按回车
**When** 下一行显示 `...>` 续行提示
**Then** 用户继续输入 `)` 后回车，两行合并发送给 agent

**Given** 用户从剪贴板粘贴一段多行代码
**When** 粘贴完成
**Then** 整段代码作为一条消息发送给 agent，而非按行拆分

---

### Story 37.7: 上下文管理

As a CLI 用户,
I want 知道当前上下文使用量，且长对话能自动压缩,
So that 对话不会因 token 溢出而失败.

**全局参数（Story 37.0 设定）：**
- 上下文窗口：200K tokens
- 自动压缩阈值：80%（160K tokens）

**实施：**

1. 上下文用量估算：
   - 每轮 stream 结束后，从 `SessionStore` 加载 transcript
   - 累计计算消息的字符数，按 1 token ≈ 4 chars 估算
   - 或从 LLM API response 的 `usage` 字段提取精确值（如果 SDK 暴露）

2. 自动 compact：
   - 在每轮 stream 开始前检查上下文用量
   - 如果 ≥160K tokens，自动触发 compact
   - Compact 策略：保留最近 3 轮完整对话 + system prompt，更早的对话压缩为摘要
   - 使用 SDK 已有的 compact 机制

3. `/compact` 命令手动触发

4. 提示符中显示用量：`axion [12k/200k]> `

**Acceptance Criteria：**

**Given** 会话已进行 10 轮对话
**When** 用户输入 `/cost`
**Then** 显示累计 token 数和预估成本

**Given** 上下文达到 160K（200K 的 80%）
**When** 用户发送新消息
**Then** 自动压缩旧对话，显示 `[axion] 上下文已压缩 (45k → 8k tokens)`
**And** 最新的 3 轮对话保持完整

**Given** 用户输入 `/compact`
**When** 命令执行
**Then** 立即压缩上下文，显示压缩前后 token 数对比

---

### Story 37.8: 会话恢复

As a CLI 用户,
I want 能恢复之前的交互会话继续对话,
So that 我关掉终端后不用从头开始.

**当前状态：**
- 已有 `ResumeCommand`（`axion resume <sessionId>`），但它走 `AxionRuntime` 路径，不支持交互模式
- ChatCommand 每次创建新 session（`chat-{UUID}`），退出后 session 保存在 `~/.axion/sessions/`

**实施：**

1. **`/resume` 命令** — 无参数列出最近会话，用户输入序号选择恢复

```
axion> /resume
最近会话:
  1. chat-a3f8b2c1  2026-06-07 13:15  5轮
  2. chat-7e4f9d0a  2026-06-07 10:30  12轮
  3. chat-1b2c3d4e  2026-06-06 22:00  3轮

选择要恢复的会话 (1-3, 或 Enter 取消): 2
[axion] 已恢复会话 chat-7e4f9d0a（12轮历史）
axion>
```

2. **会话列表扫描** — 读取 `~/.axion/sessions/` 目录，按修改时间倒序，取最近 10 个，从 transcript.json 中读取轮数

```swift
func listRecentSessions(limit: Int = 10) -> [(id: String, date: Date, turns: Int)] {
    let sessionsDir = NSHomeDirectory() + "/.axion/sessions"
    // scan directory, sort by modificationDate, read transcript for turn count
}
```

3. **恢复流程** — 用户选择后：
   - 当前 agent 关闭
   - 用选中的 sessionId 重新 build agent（SessionStore 自动加载历史）
   - 后续对话在恢复的会话上下文中继续

4. **命令行快速恢复** — `axion --resume <sessionId>` 跳过选择，直接恢复指定会话

```swift
// ChatCommand 新增参数
@Option(name: .long, help: "恢复指定会话 ID")
var resume: String?
```

5. 退出提示：`[axion] 会话 chat-a3f8b2c1 已保存，输入 /resume 可恢复`

**修改文件：**
- `Sources/AxionCLI/Commands/ChatCommand.swift` — 添加 `--resume` 参数和 `/resume` 处理
- `Sources/AxionCLI/Chat/SlashCommand.swift` — 添加 `.resume` case

**Acceptance Criteria：**

**Given** 用户在交互模式中输入 `/resume`
**When** 命令执行
**Then** 显示最近 10 个会话（序号、ID 缩写、时间、轮数）
**And** 用户输入序号后恢复对应会话
**And** 后续对话能引用恢复会话的上下文

**Given** 用户运行 `axion --resume chat-a3f8b2c1`
**When** 进入交互模式
**Then** 历史对话已加载，第一轮回复能引用之前的上下文

**Given** `/resume` 显示会话列表后
**When** 用户按 Enter（不输入序号）
**Then** 取消恢复，回到 `axion>` 提示符，当前会话不变

**Given** 用户输入 `/exit`
**When** 退出交互模式
**Then** 显示 `会话 chat-a3f8b2c1 已保存，输入 /resume 可恢复`

---

### Story 37.9: 中文输入修复

As a 中文用户,
I want 删除中文字符时按一次 backspace 就删掉整个字,
So that 输入体验流畅自然.

**问题根因：** Swift 的 `readLine()` 在某些终端下将 UTF-8 多字节字符的每个字节视为独立的 backspace 事件。

**实施方案：**

1. 检测终端编码是否为 UTF-8
2. 如果 `readLine()` 行为不正确，使用替代输入方案：
   - 方案 A：使用 Swift 的 `FileHandle.standardInput` 直接读取 raw bytes，手动处理 UTF-8 解码和 backspace
   - 方案 B：在 REPL 循环中过滤无效的中间状态（删除不完整的 UTF-8 字节序列）

3. 或采用更简单的方案：检测到不完整的 UTF-8 序列时，补齐删除

```swift
// 过滤 readLine 返回内容中的无效 UTF-8
func cleanInput(_ input: String) -> String {
    // 如果输入中包含 Unicode replacement character (U+FFFD)，
    // 说明有编码问题，尝试修复
    return input
}
```

**Acceptance Criteria：**

**Given** 用户输入了 `你好世界`
**When** 按一次 backspace
**Then** 删除 `界`，显示 `你好世`

**Given** 用户输入了 `hello`
**When** 按一次 backspace
**Then** 删除 `o`，显示 `hell`（英文行为不变）

---

## Story 间的依赖关系

```
37.0 Coding Agent 系统提示 (P0)  ← 其他所有 story 的基础
  │
  ├──► 37.1 Slash 命令体系 (P0)
  │       │
  │       ├──► 37.3 启动横幅 (P1)  ← /cost 数据来源
  │       │
  │       ├──► 37.7 上下文管理 (P1) ← /compact 实现
  │       │
  │       └──► 37.8 会话恢复 (P1)  ← /resume 列表选择
  │
  ├──► 37.2 Ctrl+C 中断 (P0)
  │
  ├──► 37.4 终端输出优化 (P1)
  │
  ├──► 37.5 权限审批 (P0)
  │
  ├──► 37.6 多行输入 (P1)
  │
  └──► 37.9 中文输入修复 (P2)
```

建议实现顺序：37.0 → 37.1 → 37.2 → 37.5 → 37.3 → 37.4 → 37.6 → 37.7 → 37.8 → 37.9

---

## 实现优先级

| Story | 优先级 | 理由 |
|-------|--------|------|
| 37.0 Coding Agent 系统提示 | P0 | 所有功能基础，当前 prompt 不适合 coding 场景 |
| 37.1 Slash 命令体系 | P0 | 交互模式基础设施，/cost、/compact、/sessions 依赖它 |
| 37.2 Ctrl+C 中断 | P0 | 基本可用性需求，无中断功能严重影响体验 |
| 37.5 权限审批 | P0 | 安全性需求，默认 bypassPermissions 太危险 |
| 37.3 启动横幅 | P1 | 信息展示，不影响核心功能 |
| 37.4 终端输出优化 | P1 | 体验提升，不影响核心功能 |
| 37.6 多行输入 | P1 | 体验提升，单行输入已可用 |
| 37.7 上下文管理 | P1 | 长对话场景必需，短对话无影响 |
| 37.8 会话恢复 | P1 | 连续工作流需求，新建会话可用 |
| 37.9 中文输入修复 | P2 | 影响中文用户，有 workaround（重输） |

---

## 关键设计约束

- **不修改 `SDKTerminalOutputHandler`** — 它被 `RunCommand` 使用，Chat 有独立格式化
- **复用 SDK 机制** — PermissionMode、SessionStore、compact 已由 SDK 提供
- **渐进式** — 每个 story 独立可用，不阻塞其他 story
- **TTY 检测** — 非交互环境（管道输入）保持简单 readLine 行为
- **向后兼容** — `axion run "task"` 行为完全不受影响
- **独立 System Prompt** — Chat 模式的 prompt 与 Run 模式完全隔离，互不影响
- **参数从 BuildConfig 传递** — 上下文窗口、maxTokens、compressionThreshold 等在 BuildConfig 中统一配置

## 现有代码参考

| 文件 | 说明 |
|------|------|
| `Sources/AxionCLI/Commands/ChatCommand.swift` | MVP 实现，~97 行 |
| `Sources/AxionCLI/Commands/ResumeCommand.swift` | 现有 resume 实现（走 AxionRuntime） |
| `Sources/AxionCLI/Commands/SDKOutputHandlers.swift` | 现有输出处理，Chat 模式不直接使用 |
| `Sources/AxionCLI/Services/AgentBuilder.swift` | BuildConfig.forCLI() 构建配置 |
| `Sources/AxionCLI/AxionCLI.swift` | defaultSubcommand 注册 |
| `Resources/prompts/planner-system.md` | 现有桌面自动化 system prompt |

## 测试策略

- **单元测试** — SlashCommand.parse()、MarkdownTerminalRenderer、权限判断逻辑、CLAUDE.md 加载
- **集成测试** — 管道输入模拟多轮对话（`printf` 方式，已在 MVP 验证中使用）
- **手动测试** — TTY 交互场景（中文输入、Ctrl+C、粘贴、多行）
- **回归测试** — 确保 `axion run "task"` 行为不受影响
- **System Prompt 测试** — 验证 coding 模式下 agent 不使用桌面自动化指令
