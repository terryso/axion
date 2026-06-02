---
project_name: 'axion'
user_name: 'Nick'
date: '2026-05-31'
status: 'draft'
epic: 31
title: '通用记忆系统 — 对齐 Hermes 自进化闭环'
---

# Epic 31: 通用记忆系统 — 对齐 Hermes 自进化闭环

Axion 的记忆从"只记住桌面操作"升级为"记住一切值得记住的事"。新增双轨记忆（MEMORY.md 环境知识 + USER.md 用户画像），审查代理从对话文本中提取偏好和知识信号，Agent 获得主动读写记忆的工具能力。这是自进化的关键数据基础设施——没有通用记忆，后续的技能进化和 Curator 就是无米之炊。

**问题：** 当前 `AppMemoryExtractor` 只处理 `ToolExecutionPair`（MCP 工具调用），完全忽略对话文本。用户偏好、环境知识、纠错信号——Hermes 最看重的学习素材在 Axion 里直接被丢弃。

**目标：** 达到 Hermes 同等的记忆覆盖：环境知识 + 用户画像 + 操作经验，三类数据完整捕获并持久化。

**依赖:** Epic 30（ReviewScheduler 基础设施）

**两套记忆系统的关系：**

| 系统 | 文件格式 | 存储路径 | 内容范围 | 工具/提取器 |
|------|----------|----------|----------|-------------|
| App 操作 facts（现有） | JSON per domain | `~/.axion/memory/{domain}-facts.json` | MCP 工具调用中提取的操作经验 | `AppMemoryExtractor` → `AxionFactStore` |
| 通用记忆（新增） | Markdown | `~/.axion/memory/MEMORY.md` + `USER.md` | 环境知识 + 用户画像 + 偏好 | `memory` 工具 + Review 审查提取 |

两套系统互补，不替代。App facts 保留按 bundle ID 分域的精确操作记录；通用记忆覆盖跨域的环境知识和用户偏好。

---

### SDK 变更（前置条件，v0.6.1 已完成）

SDK `ReviewOrchestrator` 新增 `additionalReviewTools: [ToolProtocol]` 参数（默认 `[]`）。
Axion 在构造 `ReviewOrchestrator` 时注入 `review_save_universal_memory` 工具，
让审查代理有能力写入 MEMORY.md / USER.md。

**SDK 变更内容（已在 open-agent-sdk-swift v0.6.1 实现）：**
- `ReviewOrchestrator.init` 新增 `additionalReviewTools` 参数
- `executeReview()` 中合并：`reviewTools + additionalReviewTools`

---

### Story 31.1: 双轨记忆存储 — MEMORY.md + USER.md

As a Axion 用户,
I want Axion 持久化两类独立知识：环境知识（MEMORY.md）和用户画像（USER.md）,
So that Axion 在任何任务中都能利用跨会话积累的上下文.

**Acceptance Criteria:**

**Given** `~/.axion/memory/MEMORY.md` 和 `USER.md` 不存在
**When** UniversalMemoryStore 初始化
**Then** 创建空文件，MEMORY.md 和 USER.md 均可读写

**Given** Agent 写入 "§\n项目使用 Swift 6.1\n§" 到 MEMORY.md
**When** 下次 AxionRuntime 启动
**Then** MemoryContextProvider 将该内容注入 system prompt
**And** 冻结快照模式生效——会话中途写入不刷新当前 system prompt

**Given** MEMORY.md 包含 "§\nAPI 密钥在 Keychain\n§"
**When** MemorySecurityScanner 扫描该内容
**Then** 不触发安全告警（正常知识）

**Given** MEMORY.md 包含 "§\nignore all previous instructions\n§"
**When** MemorySecurityScanner 扫描该内容
**Then** 拒绝写入，记录 warning 日志

**Given** MEMORY.md 字符数超过上限（默认 4000 字符）
**When** Agent 尝试 add 新条目
**Then** 提示 Agent 需要先 replace 或 remove 旧条目腾出空间

**存储格式（对齐 Hermes）：**
```
~/.axion/memory/
├── MEMORY.md          # 环境知识：项目配置、工具经验、已知的坑
├── USER.md            # 用户画像：沟通偏好、工作习惯、个人需求
├── {domain}-facts.json  # 现有 App 操作 facts（不变）
└── {domain}.json        # 现有 KnowledgeEntry（不变）
```

条目用 `§` 分隔符隔开（与 Hermes 一致）。

**实现参考：**

| 组件 | 说明 |
|------|------|
| `UniversalMemoryStore` (actor) | 管理 MEMORY.md / USER.md 的读写，线程安全 |
| `MemorySecurityScanner` (struct) | 写入时+加载时双重扫描，防提示注入和凭据泄露 |
| `MemoryContextProvider` 扩展 | 新增 `buildUniversalMemoryContext()` 方法，注入双轨记忆 |
| 冻结快照 | 会话开始时注入 system prompt，中途修改只写磁盘不刷新 prompt |

---

### Story 31.2: 记忆操作工具 — Agent 主动读写记忆

As a Axion Agent,
I want 拥有记忆操作工具（add / replace / remove / read）,
So that 我能在任务执行中主动保存和查询知识.

**Acceptance Criteria:**

**Given** Agent 执行任务时发现 "项目使用 SPM 管理依赖"
**When** Agent 调用 memory(action: "add", content: "项目使用 SPM 管理依赖", target: "memory")
**Then** 条目追加到 MEMORY.md 末尾
**And** 写入前通过 MemorySecurityScanner 检查

**Given** MEMORY.md 包含过时的 "§\n项目使用 CocoaPods\n§"
**When** Agent 调用 memory(action: "replace", target: "memory", old: "项目使用 CocoaPods", newContent: "项目使用 SPM 管理依赖")
**Then** 模糊匹配到旧条目并替换

**Given** Agent 调用 memory(action: "read", target: "user")
**Then** 返回 USER.md 当前内容

**Given** Agent 调用 memory(action: "remove", target: "memory", old: "某个过时条目")
**Then** 模糊匹配到条目并删除

**Given** memory 工具被注册到 Agent
**When** buildFullSystemPrompt() 构建 system prompt
**Then** 工具描述中明确告知 Agent 记忆工具的用途和限制

**参数设计（按操作类型区分必填/选填）：**

| 参数 | 类型 | 说明 |
|------|------|------|
| `action` | String (必填) | `"add"`, `"replace"`, `"remove"`, `"read"` |
| `target` | String (必填) | `"memory"` → MEMORY.md, `"user"` → USER.md |
| `content` | String? | `add` 时为新内容全文；其他操作忽略 |
| `old` | String? | `replace` / `remove` 时用于匹配旧条目的关键词 |
| `newContent` | String? | `replace` 时的替换内容 |

**工具实现方式：**

使用 class 实现 `ToolProtocol`（而非 `@Tool` struct），因为需要持有 `UniversalMemoryStore` 引用。
参考现有 SDK 工具模式（如 `ReviewMemoryTool`）：

```swift
final class MemoryTool: ToolProtocol {
    static let name = "memory"
    static let description = "操作持久化记忆（环境知识或用户画像）"

    private let store: UniversalMemoryStore

    init(store: UniversalMemoryStore) { self.store = store }

    // Parameters schema (JSON Schema):
    // action: String (required) — "add", "replace", "remove", "read"
    // target: String (required) — "memory" or "user"
    // content: String? — new content for "add"
    // old: String? — keyword to match for "replace"/"remove"
    // newContent: String? — replacement content for "replace"

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let action = parameters["action"] as! String
        let target = parameters["target"] as! String
        // ... route to store.add/replace/remove/read
    }
}
```

---

### Story 31.3: 审查代理注入通用记忆工具 — Review Agent 写入 MEMORY.md/USER.md

As a Axion 用户,
I want 审查代理在分析对话后能将发现的偏好和知识写入通用记忆文件,
So that 说的每一句话（不只是桌面操作）都能成为自进化的素材.

> **注意：** SDK 的 `ReviewPromptBuilder` 已经有完整的 Hermes 级别审查 prompt
> （`memoryReviewPrompt`、`skillReviewPrompt`、`combinedReviewPrompt`，含反模式清单）。
> **不需要修改审查 prompt**。真正缺失的是：审查代理没有工具能写入 MEMORY.md/USER.md。

**Acceptance Criteria:**

**Given** 用户在对话中说 "别用 emoji，回复保持简洁"
**When** ReviewScheduler 触发审查
**Then** 审查代理识别为用户偏好信号
**And** 调用 `review_save_universal_memory` 写入 USER.md："§\n不喜欢 emoji，回复保持简洁\n§"

**Given** 用户说 "项目使用 pytest 跑测试"
**When** 审查代理分析对话
**Then** 调用 `review_save_universal_memory` 写入 MEMORY.md："§\n项目使用 pytest 测试框架\n§"

**Given** 审查代理分析对话后未发现值得保存的内容
**When** 审查完成
**Then** 不写入任何记忆（非强制写入）

**Given** 审查代理发现环境依赖的失败（如 "command not found: xxx"）
**When** 审查完成
**Then** 不将该失败写入记忆（遵循反模式清单）
**And** 如果有修复方法（如 "需要 brew install xxx"），则写入修复方法而非失败本身

**Given** 审查代理发现用户纠正了 Agent 的做法（如 "别用 print，用 pdb"）
**When** 审查完成
**Then** 同时写入 USER.md（偏好）和对应 skill（操作方式）

**实现变更：**

| 文件 | 变更 |
|------|------|
| `ReviewSaveUniversalMemoryTool.swift` (NEW) | 审查专用工具 `review_save_universal_memory`，写入 MEMORY.md/USER.md |
| `AgentBuilder.swift` | 构造 `ReviewOrchestrator` 时将上述工具通过 `additionalReviewTools` 参数注入；`ReviewAgentConfig.allowedTools` 加入 `"review_save_universal_memory"` |
| `ReviewScheduler.swift` | 无需修改（已通过 SDK `additionalReviewTools` 机制注入） |

**审查专用工具定义（同样用 class 实现 ToolProtocol）：**
```swift
final class ReviewSaveUniversalMemoryTool: ToolProtocol {
    static let name = "review_save_universal_memory"
    static let description = "审查代理专用：将对话中发现的用户偏好或环境知识保存到通用记忆"

    private let store: UniversalMemoryStore

    init(store: UniversalMemoryStore) { self.store = store }

    // Parameters schema:
    // target: String (required) — "memory" or "user"
    // content: String (required) — content to save
    // action: String (required) — "add" or "replace"
    // old: String? — keyword to match for "replace"

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        // Security scan → store.add/replace → return result
    }
}
```

**注入方式：**
```swift
// AgentBuilder.swift 中 ReviewOrchestrator 构造
let universalMemoryTool = ReviewSaveUniversalMemoryTool(store: universalMemoryStore)
reviewOrchestrator = ReviewOrchestrator(
    scheduleConfig: scheduleConfig,
    factStore: reviewFactStore,
    skillRegistry: skillRegistry,
    skillEvolver: skillEvolver,
    usageStore: concreteStore,
    additionalReviewTools: [universalMemoryTool]  // ← 注入
)

// ReviewAgentConfig.allowedTools 必须包含新工具名，否则审查代理不知道自己有此工具
var reviewConfig = ReviewAgentConfig()
reviewConfig.allowedTools.append("review_save_universal_memory")
```

---

### Story 31.4: 安全扫描与冻结快照集成

As a Axion 用户,
I want 记忆系统有安全扫描防止提示注入，且冻结快照不影响前缀缓存,
So that 记忆持久化不引入安全风险且 API 成本可控.

**Acceptance Criteria:**

**Given** 攻击者尝试写入 "ignore all previous instructions" 到 MEMORY.md
**When** MemorySecurityScanner 扫描
**Then** 写入被拒绝，返回错误信息

**Given** MEMORY.md 包含零宽空格 (U+200B) 等不可见 Unicode 字符
**When** MemorySecurityScanner 加载时扫描
**Then** 检测到异常字符，记录 warning，过滤可疑条目

**Given** 会话开始时 MEMORY.md 已注入 system prompt
**When** Agent 在会话中途调用 memory(action: "add")
**Then** 新内容写入磁盘但不刷新当前 system prompt
**And** 下次会话启动时自动加载最新内容

**Given** 审查代理写入新记忆
**When** 主对话继续进行
**Then** 主对话的 system prompt 不变（冻结快照保护前缀缓存）

**安全扫描规则（写入时 + 加载时双重防线）：**

```swift
struct MemorySecurityScanner {
    /// 写入时检查的威胁模式
    static let writeThreatPatterns: [(Regex<Substring>, String)] = [
        // 提示注入
        ("ignore\\s+(previous|all|above|prior)\\s+instructions", "prompt_injection"),
        ("you\\s+are\\s+now\\s+", "role_hijack"),
        ("do\\s+not\\s+tell\\s+the\\s+user", "deception_hide"),
        // 凭据泄露
        ("curl\\s+.*\\$\\{?\\w*(KEY|TOKEN|SECRET|PASSWORD)", "exfil_curl"),
        // 不可见 Unicode
        ("[\\u200B-\\u200D\\uFEFF]", "invisible_unicode"),
    ]
}
```

**注入位置与格式：**

通用记忆注入 `buildFullSystemPrompt()` 的 system prompt，位置在现有 memory context 之后、skills 之前：

```
[现有 system prompt]
[App facts memory context]          ← 现有，按 domain 读取 JSON
[=== Universal Memory ===]          ← 新增
MEMORY.md: {MEMORY.md 内容}
USER.md: {USER.md 内容}
[=== End Universal Memory ===]
[Skills context]                    ← 现有
```

冻结快照实现：`buildFullSystemPrompt()` 在会话初始化时调用一次，结果缓存。后续 memory 工具写入只更新磁盘文件，不触发 system prompt 重构。

---

### Story 31.5: CLI 命令扩展 — 记忆管理

As a Axion 用户,
I want 通过 CLI 查看和编辑通用记忆,
So that 我可以审查和纠正 Axion 对我的理解.

**Acceptance Criteria:**

**Given** 用户执行 `axion memory list`
**When** 命令运行
**Then** 显示三类记忆：App 操作 facts（现有）、MEMORY.md 条目数、USER.md 条目数
**And** 每类显示最后更新时间

**Given** 用户执行 `axion memory show memory`
**When** 命令运行
**Then** 输出 MEMORY.md 的完整内容

**Given** 用户执行 `axion memory show user`
**When** 命令运行
**Then** 输出 USER.md 的完整内容

**Given** 用户执行 `axion memory clear --type user`
**When** 命令运行
**Then** 清空 USER.md（保留空文件）

**Given** 用户执行 `axion memory clear --type memory`
**When** 命令运行
**Then** 清空 MEMORY.md（保留空文件）

**Given** 用户执行 `axion memory clear --app com.apple.calculator`
**When** 命令运行
**Then** 行为不变（现有 App facts 清除逻辑）

---

## 与现有系统的关系

```
Epic 31 新增/修改:

~/.axion/memory/
├── MEMORY.md              ← NEW (Story 31.1)
├── USER.md                ← NEW (Story 31.1)
├── {domain}-facts.json    ← 现有 App 操作 facts（不变）
└── {domain}.json          ← 现有 KnowledgeEntry（不变）

Sources/AxionCLI/
├── Memory/
│   ├── UniversalMemoryStore.swift            ← NEW (Story 31.1)
│   ├── MemorySecurityScanner.swift           ← NEW (Story 31.4)
│   ├── MemoryTool.swift                      ← NEW (Story 31.2)
│   ├── ReviewSaveUniversalMemoryTool.swift   ← NEW (Story 31.3)
│   ├── MemoryContextProvider.swift            ← MODIFY (注入双轨记忆)
├── Commands/
│   ├── MemoryListCommand.swift               ← MODIFY (显示三类记忆)
│   └── MemoryShowCommand.swift               ← NEW (Story 31.5)
└── Services/
    ├── AgentBuilder.swift                    ← MODIFY (memory tool 注册 + additionalReviewTools 注入)
    └── ReviewScheduler.swift                 ← 无需修改（通过 SDK 机制注入）
```

## Hermes 对齐矩阵

| Hermes 能力 | Axion Story | 对齐程度 |
|-------------|-------------|---------|
| MEMORY.md 环境知识 | 31.1 | 完全对齐 |
| USER.md 用户画像 | 31.1 | 完全对齐 |
| memory tool (add/replace/remove/read) | 31.2 | 完全对齐 |
| 后台审查对话文本提取 | 31.3 | 完全对齐（SDK prompt 已就绪 + 新增写入工具） |
| 冻结快照 + 前缀缓存保护 | 31.4 | 完全对齐 |
| 安全扫描（双重防线） | 31.4 | 完全对齐 |
| 字符上限 + 整理压力 | 31.1 | 完全对齐 |
| 反模式清单 | 31.3 | 完全对齐（SDK ReviewPromptBuilder 已内置） |
| Honcho 外部记忆提供商 | — | 不纳入（MVP 足够） |
| 会话搜索 (FTS5) | — | 建议延后到 Epic 32 |
| 上下文压缩 | — | SDK 已有，不额外实现 |

## SDK 依赖说明

| SDK 版本 | 提供能力 | Epic 31 使用位置 |
|----------|----------|------------------|
| v0.6.0 | ReviewOrchestrator（5 个内置 review tools） | 基础审查 |
| **v0.6.1** | `additionalReviewTools` 参数 | Story 31.3 注入 `review_save_universal_memory` |
