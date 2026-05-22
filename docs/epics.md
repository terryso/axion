# Epics: Agent 自进化能力

> **Status:** Epic 21–22 Complete, Epic 23 Planning
> **Created:** 2026-05-21
> **Motivation:** 基于 Hermes Agent 自进化机制深度解析系列的研究成果，为 OpenAgentSDK 规划分层、渐进式的自进化能力。

---

## 设计哲学（从 Hermes 学到的）

1. **积极但克制** — 鼓励学习但明确划定边界（反模式清单）
2. **可逆性优先** — 只归档不删除，用 replace 而非覆盖
3. **成本意识** — 利用前缀缓存、辅助模型、间隔触发
4. **可选而非强制** — 每层都可以独立开关
5. **纵深防御** — 安全扫描在写入时和加载时都执行

---

## Epic 21: 记忆进化 — ExperienceExtractor 与自动审查

**目标：** 让 Agent 在会话结束时自动从对话中提炼值得持久化的经验，写入 FactStore。

**价值：** 用户花了 30 分钟教的偏好，下次对话全忘了——这是架构缺陷，不是模型能力问题。记忆进化是闭环学习的基础。

### Story 21.1: ExperienceExtractor 协议与信号模型

定义从对话中提取经验的抽象接口和数据模型。

**产出：**
- `ExperienceSignal` struct — 经验信号（内容、领域、类型、置信度）
- `ExperienceExtractor` protocol — 抽象接口，输入 `[SDKMessage]`，输出 `[ExperienceSignal]`
- `ExtractionConfig` — 配置项（反模式清单、信号阈值）

**Hermes 参考：**
- `agent/background_review.py` — `_MEMORY_REVIEW_PROMPT` 和 `_COMBINED_REVIEW_PROMPT` 定义了审查逻辑
  - 重点关注：审查 prompt 的两段式结构（记忆审查 + 技能审查）
  - 记忆审查聚焦两类信号：用户身份（persona, preferences）和用户期望（work style, behavior）
  - 组合审查 prompt 的格式和措辞（"Be ACTIVE" vs "Nothing to save" 的平衡）

**现有 SDK 基础：**
- `Types/MemoryFact.swift` — `MemoryFact` 已有完整的生命周期（candidate→active→retired）、置信度、证据计数
- `Types/MemoryTypes.swift` — `KnowledgeEntry` 和 `MemoryStoreProtocol` 已定义存储抽象
- `Stores/FactStore.swift` — 持久化存储已实现（actor、JSON 文件、legacy 迁移）

### Story 21.2: LLMExperienceExtractor — LLM 驱动的经验提取器

用 LLM 调用来从对话中提取经验信号的内置实现。

**产出：**
- `LLMExperienceExtractor` — 基于 LLM 的 ExperienceExtractor 实现
- 审查 prompt 模板（包含反模式清单）
- 冻结快照模式：提取结果写入磁盘但不刷新当前 system prompt

**Hermes 参考：**
- `agent/background_review.py:1-145` — 完整的后台审查实现
  - `_MEMORY_THREAT_PATTERNS` (第 34-37 行) — 提示注入检测模式
  - `_COMBINED_REVIEW_PROMPT` — 组合审查 prompt，同时处理记忆和技能
  - **反模式清单**（第 121-144 行）：
    - 环境依赖的失败（missing binaries, command not found）
    - 负面断言（"browser tools do not work"）
    - 一次性瞬态错误（重试就好的那种）
    - 一次性任务叙述（"summarize today's market"）
  - **关键措辞**："If a tool failed because of setup state, capture the FIX — never 'this tool does not work' as a standalone constraint"
- `tools/memory_tool.py:67-100` — 记忆安全扫描
  - `_MEMORY_THREAT_PATTERNS` — 写入时的威胁模式检测（prompt injection, exfil, SSH backdoor）
  - `_INVISIBLE_CHARS` — 不可见 Unicode 字符检测
  - `_scan_memory_content()` — 写入时扫描函数

**现有 SDK 基础：**
- `API/LLMClient.swift` — 可复用现有 LLM 客户端做提取
- `Utils/MemoryContextProvider.swift` — 已有将 facts 格式化为 prompt 的能力

### Story 21.3: ReviewHook — sessionEnd 自动审查接入

将 ExperienceExtractor 接入 HookRegistry 的 `sessionEnd` 事件，完成记忆进化的闭环。

**产出：**
- `MemoryReviewHook` — 注册到 `sessionEnd` 的 hook 实现
- 间隔控制：不是每次会话都审查，通过配置控制间隔
- 操作摘要：审查完成后生成人类可读的摘要

**Hermes 参考：**
- `agent/background_review.py:1-40` — 触发条件和间隔控制
  - `_memory_nudge_interval` 和 `_skill_nudge_interval` — 审查间隔配置
  - 三个条件同时满足才触发：有最终回复、对话未中断、达到审查间隔
- `agent/background_review.py` — `spawn_background_review()` 函数
  - Fork 审查代理，继承父代理的 `model`, `provider`, `api_key`, `base_url`
  - **前缀缓存共享**：`review_agent._cached_system_prompt = agent._cached_system_prompt`
  - `session_start` 和 `session_id` 固定以保证缓存一致
  - 审查代理工具白名单：只允许 `memory`, `skill_manage`, `skill_view`, `skills_list`
  - `summarize_background_review_actions()` — 提取人类可读的操作摘要

**现有 SDK 基础：**
- `Hooks/HookRegistry.swift` — 已有 `sessionEnd` 事件
- `Types/HookTypes.swift` — `HookEvent.sessionEnd` 已定义

### Story 21.4: 记忆安全扫描与冻结快照

防止记忆被武器化，确保前缀缓存不被破坏。

**产出：**
- 写入时扫描：威胁模式检测（prompt injection、exfil、SSH backdoor）
- 加载时扫描：系统提示词构建时扫描所有注入的上下文
- 不可见 Unicode 字符检测
- 冻结快照模式：会话中写入 fact 不刷新 system prompt

**Hermes 参考：**
- `tools/memory_tool.py:67-100` — 完整的安全扫描实现
  - `_MEMORY_THREAT_PATTERNS` — 13 种威胁模式
  - `_INVISIBLE_CHARS` — 6 种不可见 Unicode 字符
  - `_scan_memory_content()` — 写入时扫描
  - `_INVISIBLE_CHARS` 集合 — U+200B, U+200C, U+200D, U+2060, U+FEFF, U+202A-E
- `tools/memory_tool.py` (docstring) — 冻结快照设计说明
  - "Mid-session writes update files on disk immediately (durable) but do NOT change the system prompt — this preserves the prefix cache for the entire session."
- `agent/background_review.py:70-75` — 缓存继承实现
  - 审查代理继承 `_cached_system_prompt`、`session_start`、`session_id`
  - 字节级一致保证前缀缓存命中
  - PR #17276 分析：约 26% 端到端成本降低

**现有 SDK 基础：**
- `Stores/FactStore.swift` — 已有 `validateDomainName()` 做路径遍历防护
- `Utils/MemoryContextProvider.swift` — 系统提示词注入的入口

---

## Epic 22: 技能进化 — SkillEvolver 与生命周期管理

**目标：** 让 Agent 能从对话中自动创建、更新、归档技能，实现「从经验中提炼可复用的操作指南」。

**价值：** 记忆解决「你是谁、世界是什么样的」，技能解决「这类事该怎么做」。技能是 Agent 的程序性知识——跨会话可复用的操作指南。

### Story 22.1: SkillSignal 模型与 SkillEvolver 协议

定义技能变更信号和进化器接口。

**产出：**
- `SkillSignal` struct — 技能变更信号（skillName、signalType、content、confidence、source）
- `SkillEvolver` protocol — 技能进化器抽象接口
- `SkillLifecycleState` — active / deprecated / experimental / retired 状态机

**Hermes 参考：**
- `tools/skill_usage.py:1-100` — 技能生命周期管理
  - `STATE_ACTIVE`, `STATE_STALE`, `STATE_ARCHIVED` — 三态定义
  - `_usage_file()` → `~/.hermes/skills/.usage.json` — 使用追踪 sidecar 文件
  - 设计决策：sidecar 而非 frontmatter，"keeps operational telemetry out of user-authored SKILL.md content"
  - `provenance` 字段：`agent_created` / `bundled` / `hub_installed` — 来源追踪
  - 原子写入：`tempfile + os.replace` 模式
  - 文件锁：`fcntl` (Unix) / `msvcrt` (Windows) 跨进程序列化
- `tools/skill_manager_tool.py:1-80` — 技能管理工具
  - 动作定义：`create`, `edit`, `patch`, `delete`, `write_file`, `remove_file`
  - 目录布局：`~/.hermes/skills/<skill>/SKILL.md + references/ + templates/ + scripts/`
  - 安全扫描：`skills_guard.scan_skill()` 对外部安装的技能

**现有 SDK 基础：**
- `Types/SkillTypes.swift` — `Skill` struct 已有 `baseDir`, `supportingFiles` 字段
- `Tools/SkillRegistry.swift` — 已有技能注册和查找
- `Skills/SkillLoader.swift` — 已有从文件系统加载技能

### Story 22.2: LLMSkillEvolver — LLM 驱动的技能进化

用 LLM 调用来识别技能信号并执行技能变更。

**产出：**
- `LLMSkillEvolver` — 基于 LLM 的 SkillEvolver 实现
- 技能审查 prompt（类级命名约束、优先修补策略、用户偏好嵌入）
- 内存中 Skill 字段合并（promptTemplate、description、whenToUse 等字段级别的 partial override，不涉及文件系统操作）

**Hermes 参考：**
- `agent/background_review.py:45-145` — `_SKILL_REVIEW_PROMPT` 完整内容
  - **触发信号**（4 类）：
    1. 风格纠正（"stop doing X", "too verbose"）
    2. 流程纠正（"先写测试再写代码"）
    3. 新技术（workaround、debugging path）
    4. 技能过时（loaded skill turned out wrong）
  - **优先级顺序**：
    1. UPDATE A CURRENTLY-LOADED SKILL
    2. UPDATE AN EXISTING UMBRELLA
    3. ADD A SUPPORT FILE
    4. CREATE A NEW CLASS-LEVEL UMBRELLA（最后手段）
  - **类级命名约束**：名称不能是 PR number、error string、feature codename
  - **用户偏好嵌入**：preferences belong in SKILL.md body, not just in memory
  - **三种支持文件**：`references/`（参考文档）、`templates/`（模板）、`scripts/`（脚本）
- `tools/skill_manager_tool.py:1-80` — 技能文件操作
  - `skill_manage(action="create/edit/patch/delete/write_file/remove_file")`
  - `_guard_agent_created_enabled()` — 代理创建的技能安全扫描开关
  - `_security_scan_skill()` — 安全扫描函数

### Story 22.3: SkillUsageTracker — 使用追踪与生命周期转换

追踪技能使用频率，自动执行生命周期状态转换。

**产出：**
- `SkillUsageTracker` — 追踪 view_count、last_viewed_at、last_managed_at
- 生命周期转换：active → deprecated（30天）→ retired（90天）
- Pinned 技能跳过所有自动转换
- 使用追踪 sidecar 文件（与技能内容分离）

**Hermes 参考：**
- `tools/skill_usage.py:1-100` — 完整的使用追踪实现
  - `bump_view(skill_name)` — 增加查看计数
  - `bump_manage(skill_name)` — 更新管理时间戳
  - `get_usage(skill_name)` — 获取使用数据
  - `get_provenance(skill_name)` — 获取技能来源
  - `set_provenance(skill_name, provenance)` — 设置来源
  - `_usage_file_lock()` — 文件锁（fcntl/msvcrt）
  - 原子写入：`tempfile + os.replace`（`.usage.json`）
  - 追踪字段：`view_count`, `last_viewed_at`, `last_managed_at`, `state`, `pinned`, `provenance`

**现有 SDK 基础：**
- `Types/SkillTypes.swift` — `Skill` struct 可扩展 lifecycle state

### Story 22.4: Curator — 自动策展人

在 Agent 空闲时自动整理技能库：合并重叠、归档过期、修补技能。

**产出：**
- `SkillCurator` — 策展人服务
- 触发条件：代理空闲 + 距上次策展超过配置间隔（默认 7 天）
- 安全边界：只操作 agent_created 技能，不碰内置/Hub/用户 pinned 技能
- 策展状态持久化（last_run_at、paused、run_count）
- dry-run 模式

**Hermes 参考：**
- `agent/curator.py:1-200` — Curator 完整实现
  - `_default_state()` — 默认状态（last_run_at, paused, run_count）
  - `load_state()` / `save_state()` — 状态持久化（JSON + 原子写入）
  - `is_enabled()` — 默认开启
  - `get_interval_hours()` — 默认 7 天（168 小时）
  - `get_min_idle_hours()` — 默认 2 小时
  - `get_stale_after_days()` — 默认 30 天
  - `get_archive_after_days()` — 默认 90 天
  - `should_run_now()` — 判断是否该运行
  - `_strip_aux_credential()` — 辅助模型凭据处理
  - 不变量：只操作 agent_created 技能、永不自动删除、pinned 跳过转换

---

## Epic 23: 高级进化 — 插件生态（可选）

**目标：** 提供插件化的高级自进化能力，让开发者按需集成。

**价值：** 会话搜索、prompt 进化优化等是锦上添花的能力，不适合纳入核心 SDK，更适合作为可插拔模块。

### Story 23.1: SelfEvolutionPlugin 协议与插件注册

定义自进化插件的统一接入协议。

**产出：**
- `SelfEvolutionPlugin` protocol — 统一接口
- `PluginRegistry` — 插件注册和生命周期管理
- 插件配置 schema（`AgentOptions` 中新增 `evolutionPlugins` 字段）

**Hermes 参考：**
- `tools/memory_tool.py` 中 `MemoryProvider` 抽象类（博客文章第二篇提到）
  - `initialize(session_id)` — 会话初始化
  - `system_prompt_block()` — 注入系统提示词
  - `prefetch(query)` — 每轮预取
  - `sync_turn(user_msg, assistant_resp)` — 每轮同步
  - `get_tool_schemas()` / `handle_tool_call()` — 工具暴露
  - `on_session_end(messages)` — 会话结束钩子
  - `on_pre_compress(messages)` — 压缩前提取
  - **一家一限制**：只允许一个外部记忆提供商

**现有 SDK 基础：**
- `Hooks/HookRegistry.swift` — 已有插件式 hook 注册机制
- `Tools/MCP/MCPClientManager.swift` — MCP 外部工具集成的模式可参考

### Story 23.2: SessionSearchPlugin — 会话全文搜索

基于 SQLite FTS5 的会话搜索，让 Agent 回溯过往所有对话。

**产出：**
- `SessionSearchPlugin` — FTS5 全文搜索插件
- 三种搜索模式：发现（关键词）、滚动（特定会话浏览）、浏览（最近会话）
- 搜索结果带上下文窗口（匹配片段前后各 5 条消息）
- 零 LLM 成本（纯数据库操作）
- 暴露为 MCP 工具或内置工具

**Hermes 参考：**
- `agent/trajectory.py` — 会话存储和搜索（博客第五篇提到）
  - SQLite 数据库存储所有对话
  - FTS5 全文搜索引擎
  - `session_search(query=)` — 关键词搜索
  - `session_search(session_id=, around_message_id=)` — 会话内浏览
  - `session_search()` — 最近会话列表
  - 搜索结果结构：匹配片段 + 前后 5 条消息 + 会话开头 3 条 + 会话结尾 3 条

**现有 SDK 基础：**
- `Stores/SessionStore.swift` — 已有会话持久化
- `HTTP/RunPersistenceService.swift` — Run 持久化
- `Utils/TraceRecorder.swift` — JSONL 轨迹记录

### Story 23.3: PromptEvolverPlugin — 进化式 Prompt 优化

用进化算法优化 skill 的 promptTemplate，提升技能质量。

**产出：**
- `PromptEvolverPlugin` — 可选的 prompt 进化优化插件
- Organism（有机体）/ Evaluator（评估者）/ Mutator（变异者）三组件
- 进化参数配置（种群大小、轮次、适应度函数）
- 适配 `Skill.promptTemplate` 作为进化目标

**Hermes 参考：**
- `agent/trajectory.py` + 可选技能 — Darwinian Evolver（博客第五篇提到）
  - 来源：Imbue Research 的 `darwinian_evolver`
  - 工作流：初始种群 → 评估适应度 → 选择最优 → LLM 变异 → 重复 N 轮
  - Organism：被进化的对象（prompt 模板、正则、SQL、代码）
  - Evaluator：打分函数 [0, 1]，区分"可训练失败"和"保留失败"
  - Mutator：LLM 基于失败案例生成变体
  - 成本：50-500 次 LLM 调用/次，适用于值得优化的 prompt

---

## 架构总览

```
┌─────────────────────────────────────────────────────────┐
│                   OpenAgentSDK                          │
│                                                         │
│  ┌───────────────────────┐  ┌────────────────────────┐  │
│  │  Epic 21: 记忆进化     │  │  Epic 22: 技能进化      │  │
│  │                       │  │                        │  │
│  │  ExperienceExtractor  │  │  SkillEvolver          │  │
│  │  LLMExperienceExtract │  │  LLMSkillEvolver       │  │
│  │  MemoryReviewHook     │  │  SkillUsageTracker     │  │
│  │  记忆安全扫描          │  │  SkillCurator          │  │
│  │  冻结快照模式          │  │  生命周期管理           │  │
│  └───────────┬───────────┘  └────────────┬───────────┘  │
│              │                           │              │
│              └──────────┬────────────────┘              │
│                         │                               │
│              ┌──────────┴──────────┐                    │
│              │    HookRegistry     │                    │
│              │  sessionEnd hook    │                    │
│              │  postToolUse hook   │                    │
│              └─────────────────────┘                    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │  Epic 23: 高级进化插件（可选）                     │    │
│  │  SessionSearchPlugin                             │    │
│  │  PromptEvolverPlugin                             │    │
│  │  ExternalMemoryPlugin (via MCP)                  │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

## 现有 SDK 与 Hermes 的能力对照

| 自进化能力 | Hermes 实现 | SDK 现状 | Epic |
|-----------|------------|---------|------|
| 持久记忆存储 | MEMORY.md + USER.md | `FactStore` + `MemoryFact` ✅ | 21 |
| 经验提取引擎 | background_review.py | `LLMExperienceExtractor` + `ExperienceExtractor` protocol ✅ | 21 |
| 记忆安全扫描 | memory_tool.py threat patterns | `MemorySecurityScanner` + `SecurityScanResult` ✅ | 21 |
| 冻结快照模式 | 会话开始注入、中途不刷新 | `FrozenSnapshot` + `FactStore.snapshot/rollback` ✅ | 21 |
| 技能定义与加载 | SKILL.md + SkillLoader | `Skill` + `SkillRegistry` ✅ | 22 |
| 技能自动创建/更新 | skill_manage + background review | 缺 ❌ | 22 |
| 技能使用追踪 | skill_usage.py sidecar | 缺 ❌ | 22 |
| 技能生命周期 | active→stale→archived | 缺 ❌ | 22 |
| 自动策展 | curator.py | 缺 ❌ | 22 |
| 会话搜索 | SQLite FTS5 | 缺 ❌ | 23 |
| Prompt 进化 | Darwinian Evolver | 缺 ❌ | 23 |
| 轨迹压缩 | trajectory_compressor.py | `TraceRecorder` 部分 ✅ | 23 |

## Hermes 关键源码索引

| 文件 | 路径 | 核心内容 |
|------|------|---------|
| 后台审查 | `agent/background_review.py` | `_MEMORY_REVIEW_PROMPT`, `_SKILL_REVIEW_PROMPT`, `_COMBINED_REVIEW_PROMPT`, fork 逻辑 |
| 记忆工具 | `tools/memory_tool.py` | 安全扫描、冻结快照、`§` 分隔符、字符限制 |
| 技能管理 | `tools/skill_manager_tool.py` | create/edit/patch/delete/write_file 动作 |
| 技能使用 | `tools/skill_usage.py` | 生命周期状态、使用追踪、文件锁、原子写入 |
| 策展人 | `agent/curator.py` | 间隔触发、策展状态、安全边界、dry-run |
| 轨迹压缩 | `trajectory_compressor.py` | 训练数据准备、结构化摘要 |
