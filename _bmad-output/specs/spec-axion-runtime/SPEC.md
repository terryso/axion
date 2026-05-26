---
id: SPEC-axion-runtime
companions:
  - event-taxonomy.md
  - api-protocol.md
  - state-machines.md
  - architecture-diagrams.md
  - implementation-roadmap.md
sources:
  - ~/Desktop/axion/prd.md
  - ~/Desktop/axion/architecture.md
  - ~/Desktop/axion/runtime-model.md
  - ~/Desktop/axion/runtime-api-spec.md
  - ~/Desktop/axion/axion-runtime-roadmap.md
  - ~/Desktop/axion/sdk-runtime-roadmap.md
---

> **规范合约。** 本 SPEC 及 `companions:` 中列出的文件构成完整的、经保真验证的构建/测试/验收合约。frontmatter 中列出的源文件仅用于溯源——仅在需要叙述背景或语色彩色时查阅。

# Axion Agent Runtime 平台

## Why

当前 AI 编码工具（Claude Code、Cursor、Aider）将执行视为一次性聊天会话：断开即丢失上下文，workflow 无持久性，执行过程不透明。使用 BMAD/LangGraph/CrewAI 的开发者面临高 token 成本，却无法调试执行过程或观测 agent 行为。同时，macOS 原生生态缺少 Swift 实现的 agent runtime。Axion 要同时解决三个问题：**执行临时性**（终端关闭即 session 消失）、**agent 不可观测**（用户看不到决策、工具调用、上下文演化、token 成本）、**workflow 困在聊天形态**（无结构化任务分解或执行图）。机会在于基于已有的 `open-agent-sdk-swift` 构建一个 Swift 原生 runtime，使 agent 执行可持久、可重放、可观测、可组合。

## Capabilities

- id: CAP-1
  intent: 开发者可以创建跨进程持久化的 session，断开连接或崩溃后可恢复执行状态。
  success: `axion resume <session-id>` 恢复完整对话上下文，agent 从上次中断处继续，包括跨 CLI 进程退出后的恢复。

- id: CAP-2
  intent: 开发者通过统一的 event stream 观测 agent session 的完整执行生命周期——agent 决策、工具调用、上下文变化、memory 更新、token 成本。
  success: 订阅某个 session 的 event stream 可获得按时间排序的完整状态变化追踪，足以重建 timeline 视图，无需查阅其他数据源。

- id: CAP-3
  intent: 开发者可以定义并执行结构化 workflow（顺序或 DAG 结构），编排多个专业 agent（planner、researcher、implementer、reviewer），支持共享或隔离上下文。
  success: YAML 定义的 4-agent workflow 按依赖顺序执行，event stream 中可见每个 agent 的生命周期事件及父子关系。

- id: CAP-4
  intent: 开发者可以从 event log 重放任意已完成或暂停的 session，重建任意时间点的精确执行状态。
  success: `axion replay <session-id>` 在相同 event 序列下产生与原运行相同的执行状态和 workflow 图。确定性重放有保证。

- id: CAP-5
  intent: 开发者可以通过 runtime daemon 在后台/分离模式运行 agent 任务，daemon 维护 workflow 状态、管理 event stream、处理多个并发 session 的持久化。
  success: `axion run "task" &` 后台执行；daemon 在终端关闭后继续运行，session 可被重新 attach。

- id: CAP-6
  intent: 多个前端（CLI、HTTP API、TUI、macOS App）通过订阅 EventBus 消费同一 agent 执行，前端不持有状态也不直接调用工具。
  success: CLI 和 HTTP API session 通过同一 EventBus 发出相同类型的 event；测试订阅者无论哪个前端发起 session 都收到相同事件。

- id: CAP-7
  intent: 开发者通过 event stream 实时追踪每个 agent 和每个 workflow 的 token 用量和成本。
  success: 每次 LLM 调用后发出 LLMCostEvent，包含 input/output token 数和计算成本；汇总 session 的 event 可得到总花费。

- id: CAP-8
  intent: 横切关注点（visual delta 追踪、seat monitoring、memory 处理、review 编排、通知）作为独立 event handler 运行，而非执行循环中的内联逻辑。
  success: 每个 handler 独立可测试、可订阅、可组合——CLI 注册全套，API 注册子集——无需修改核心执行路径。

- id: CAP-9
  intent: 开发者通过 CLI 命令查看运行中和已完成的 session——session 列表、状态、上下文和产物。
  success: `axion sessions` 返回所有 session 及其状态和时间戳；session 状态转换（CREATED → RUNNING → PAUSED/COMPLETED/FAILED）可查询。

- id: CAP-10
  intent: 开发者可以将 Axion 与 macOS 原生能力集成，包括文件系统监控（FSEvents）、Accessibility API 和 AppleScript。
  success: agent session 可以使用 FSEvents 监听文件变化和 Accessibility API 操作 UI 元素，工具调用在 event stream 中可见。

## Constraints

- 必须使用 Swift，基于 structured concurrency（async/await、AsyncSequence、actor）。Runtime 路径中禁止 Node.js、Python 或 Electron。
- 所有状态变化必须以 event 表达——不允许隐藏状态，不允许在 EventBus 外直接变更状态。
- Event log 只追加，不修改、不删除已持久化的 event。这是确定性重放的基础。
- UI 层（CLI、TUI、App）不持有状态、不直接调用工具、不管理 workflow。UI 只消费 event stream。
- 基于已有的 `open-agent-sdk-swift` 构建——Axion 扩展 SDK，不 fork 不替换。AgentOptions.eventBus 为可选注入；不传 EventBus 时行为不变。
- Session 恢复必须在 1 秒内完成；event stream 延迟不超过 100ms。
- Crash-safe event log——进程崩溃时 event 不丢失。

## Non-goals

- SaaS 平台或多租户托管。Axion 是本地开发者工具。
- Web IDE 或浏览器产品。
- 可视化/no-code workflow 构建器。Workflow 用 YAML 定义。
- 团队协作功能（共享 session、权限管理、多用户）。
- v1 不做跨进程 EventBus——daemon 在单进程内处理多 session；remote runtime 是未来方向。
- 分布式 workflow 执行。
- Prompt marketplace。
- 修改 SDKMessage——对现有 SDK 消费者完全向后兼容。

## Success signal

开发者执行 `axion run "重构认证模块"`，关闭终端，重新打开后执行 `axion resume <id>`，agent 带着完整上下文继续工作。Event stream 按时间顺序展示每个工具调用、token 成本和 agent 决策。另一开发者通过 HTTP API 连接同一 daemon，实时看到相同的 event stream。无隐藏状态、无丢失上下文、无"agent 到底做了什么"的疑问。

## Assumptions

- `open-agent-sdk-swift` Epic 1（AgentEvent 协议 + EventBus）会在 Axion Epic 1 之前或同时交付；Axion 开发期间可用 mock EventBus。
- SDK 的 `SessionStore` 提供正确的 session 持久化，支持跨进程恢复。
- v1 的主要传输层是 STDIO（CLI）；TUI/App 的 WebSocket 传输延后。
- v1 用 SQLite 做 event log 足够；不需要更重的持久化引擎。
- Phase 1 范围是 A1–A4（EventBus 集成、AxionRuntime actor、EventHandler 体系、CLI 迁移）。A5–A7（API 迁移、session resume CLI、daemon）为 P1/P2 后续。

## Open Questions

- EventBus 缓冲策略是否需要区分 CLI（小缓冲、低延迟）和 daemon 模式（大缓冲、吞吐优先）？当前提案是所有模式统一 bufferingLatest(100)。
- Token streaming event（LLMTokenStreamEvent）性能开销大——应该是按 session 开关还是全局配置？
- runtime-model.md 提出 agent 间只通过 event 通信、不共享可变状态——这是否适用于 SDK 已有的 SubAgent/Team API（可能使用共享上下文）？
- 路线图提出 YAML workflow 定义，但 runtime-model 描述了 DAG 支持——Phase 1 是否只支持顺序 workflow，DAG 延后到 Phase 3？
