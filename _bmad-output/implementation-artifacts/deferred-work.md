# Deferred Work

## Deferred from: code review of 1-2-helper-mcp-server-foundation (2026-05-08)

- ToolNames.swift missing constants for hotkey/scroll/list_apps/get_window_state/drag — these tools are stubs in 1.2, constants will be needed when implementing in 1.3-1.5
- ToolRegistrar.swift is a single 262-line file — will need splitting when tools get real implementations in 1.3-1.5, acceptable for stub phase, restructure during real implementation
- Process smoke test has fragile timing (200ms sleep after launch) — acceptable trade-off for integration tests, can be improved with retry logic later

## Deferred from: code review of 2-3-axion-setup-first-time-config (2026-05-09)

- `CGPreflightScreenCaptureAccess()` triggers system dialog on macOS — no pure "check-only" API exists for screen recording permission. This is an Apple API limitation. Acceptable for now; may need documentation in user-facing help text.
- `maskApiKey` reveals 9/10 characters for keys of exactly length 10 — spec design gap. Real Anthropic API keys are 100+ chars so practical risk is negligible. Spec masking policy could be tightened in a future iteration.
- `PermissionChecker` uses static methods with no protocol abstraction — not mockable for testing. Story 2.4 (axion doctor) will reuse this and may need to introduce a protocol at that point.

## Deferred from: code review of 3-2-prompt-management-planning-engine (2026-05-10)

- `resolvePromptDirectory()` fallback returns a path that may not exist, leading to unclear error messages when prompts directory is missing — not introduced by this story, pre-existing design choice that can be improved in a future iteration

## Deferred from: code review of 4-3-memory-enhanced-planning (2026-05-13)

- Tight JSON format coupling in MemoryListCommand — MemoryListCommand directly parses FileBasedMemoryStore's JSON format. Fragile if SDK changes serialization, but covered by tests using FileBasedMemoryStore.
- No test for `--no-memory` flag at RunCommand level — AC4 flag is only verified at the MemoryContextProvider level, not as an end-to-end RunCommand test. Requires integration test infrastructure.

## Deferred from: code review of 5-2-sse-event-stream-realtime-progress (2026-05-13)

- batch_completed 事件类型缺失 — spec AC1 列出 batch_completed 但 Dev Notes 和 Tasks 中均未定义其数据结构。当前架构中 AgentRunner 不跟踪 batch 概念。spec ambiguity, 可在未来需求出现时添加。
- RunTracker.print() 警告未使用日志系统 — Story 5.1 遗留代码，不归本 Story 负责。应在统一日志重构时处理。

## Deferred from: Epic 21 Phase 2 code review (2026-05-21)

- RunCompleteContextBox (`AgentBuilder.swift:11-13`) is `@unchecked Sendable` with a mutable `var context` — onRunComplete closure writes, RunOrchestrator reads. No synchronization. Currently safe because SDK stream processing is sequential, but fragile if SDK changes concurrency model.
- Split-brain tracker IDs in ServerCommand.runHandler — RunCoordinator generates its own runId via `submitRun()`, then passes it to SDK's `tracker.updateRun(runId:)` which doesn't know that ID. SDK and Axion track runs independently. Tests pass because SDK routes and Axion custom routes are tested separately. Should be unified by either passing SDK's runId through to RunCoordinator or eliminating dual tracking.

## Deferred from: Epic 29 验收 (2026-05-30)

- TG 持续会话 — 当前每条 TG 消息创建新 agent session（`executeRun()`），用户无法基于上次结果追问。改进方案：`TaskSerialQueue` 维护 `chatId → sessionId` 映射，用 `resumeSession()` 替代 `executeRun()`，30 分钟无消息自动关闭会话，用户可发 `/new` 主动开始新会话。

## Deferred from: TG Persistent Sessions review (2026-05-30)

- Resume degradation double timeout — when `resumeRun()` fails and degrades to `executeNewWithTimeout()`, the task gets a fresh full timeout. Worst case ~20 min wall clock for default 10 min timeout. Acceptable tradeoff for simplicity; could be improved by tracking elapsed time.
- `chatSessions` unbounded growth — `TaskSerialQueue.chatSessions` has no eviction policy for distinct chatIds. For a small-user-count TG bot this is fine. Should add a max-entries eviction (similar to `DaemonRuntimeManager.maxSessionHistory`) if user count grows.

## Deferred from: TG Message UX Simplification spec split (2026-06-01)

- Broader Hermes-parity polish — add Telegram message reactions / notification-mode tuning / richer processing indicators only after the core chat-noise cleanup ships.

## Deferred from: TG Message UX Simplification review (2026-06-01)

- Group-chat session isolation — `TaskSerialQueue` resumes Telegram sessions by `chatId` only, so different users in the same group chat could inherit each other’s resumed context. Out of scope for this UX cleanup; address in a focused session-keying follow-up.

## Deferred from: /skills 命令 + /skill-name 直接执行 (2026-06-10)

- SlashPopup skill 补全 — 输入 `/` 时 popup 只显示内置 slash 命令，不显示 skill 名称。需要重构 `SlashPopupItem` 数据模型（当前强绑定 `SlashCommand` 枚举），引入 `SlashPopupItemKind`（`.command(SlashCommand)` | `.skill(name:description:)`）以支持 skill 名称出现在补全列表中。工作量较大（涉及 SlashPopup、ComposerSlashPopupHandling、ChatComposer 多处），建议独立 story 处理。核心功能（`/skills` 列表 + `/skill-name` 直接执行）已完成。

## Deferred from: code review of /apps 扫描加载提示 (2026-06-13)

- `SpinnerRenderer.startAnimation(message:)` 入口未 guard `isStopped` — 延迟启动（delayMs>0）路径下，若 `stop()` 在延迟 handler 已 dispatch 但未执行之间被调用，晚到的 handler 会无条件 `startAnimation` 复活一个空转的 animationTimer（每帧被 `isStopped` 拦截不写屏，但定时器已复活）。当前 `/apps` 调用方被 `defer { spinner.stop() }` 安全网完全掩盖，无可观测 bug。修复：在 `startAnimation` 首行加 `guard !isStopped else { return }`。共享组件，也保护"思考中" spinner（同样用 delayMs:500）。
- ~~App 扫描中途不可取消 — Ctrl+C 中断深度扫描（含 mdfind 3s 超时 + homebrew 枚举）时，`AppListService.list()` 内部不检查取消、不抛错，spinner 会持续动画直到扫描自然结束。预存在的扫描不可取消性，加了 spinner 后更明显。修复需动 `service.list`（本 spec 明确 Never），建议独立 story：用 `withTaskCancellationHandler` 包裹或检查 `Task.isCancelled` 提前 break。~~ **【已解决 2026-06-13，见 spec-apps-cancel-scan：list() 加协作式取消检查点 + 扫描期间 EscapeInterruptListener 统一捕获 Esc(0x1B)/Ctrl+C(0x03)】**
- （次要/外观）`listAppsForSlash` 中 `let start = Date()` 在 fast 路径是死代码（仅 deep 块使用）— 可移入 `if scope == .deep` 块。预存在、非本 story 引入。

## Deferred from: MCP Server 用户可配置化 review (2026-06-13)

- Remote MCP auth headers — `AxionMcpServerConfig.sse/http` currently accept only `url`, so authenticated SSE/HTTP MCP servers cannot be declared in `~/.axion/config.json`. Add optional `headers: [String: String]` to remote config cases and docs in a focused follow-up.
