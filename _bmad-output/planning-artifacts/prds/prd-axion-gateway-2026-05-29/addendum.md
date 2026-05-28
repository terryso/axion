# Addendum — Axion Gateway PRD

技术参考和设计对比，不直接属于 PRD 主体的内容。

---

## Hermes vs Axion 自进化对比

| 维度 | Hermes | Axion（PRD 后） |
|------|--------|----------------|
| 语言 | Python | Swift |
| Memory 模型 | MEMORY.md + USER.md（双轨文件） | AppMemoryFact（per-app domain，evidence/confidence 状态机） |
| Skill 模型 | SKILL.md（Markdown） | JSON 录制 + SKILL.md（Markdown） |
| 审查触发 | conversation_loop 结尾 fork thread | ReviewHandler（EventBus handler on AgentCompletedEvent） |
| 审查执行 | fork AIAgent + 共享前缀缓存 | 需增强：通过 AxionRuntime 创建独立 agent 实例 |
| Curator 触发 | 空闲 2h + 7 天间隔 | CuratorScheduler（gateway 进程内定时检查） |
| Curator 执行 | fork AIAgent + 工具白名单 | IntelligentCurator + LLMSkillEvolver（已有） |
| 渠道 | 20+ 平台 adapter | MVP: TG only |
| 进程模型 | GatewayRunner（单进程多线程） | GatewayRunner（单进程 Swift Concurrency） |
| 安全模型 | per-platform env var allowlist | TG: bot token + user ID allowlist（参考 Hermes） |

## Hermes 设计哲学借鉴

### 1. 积极但克制

审查 agent 被告知"什么都不做是错失学习机会"，但被明确禁止捕获环境依赖和负面断言。

**Axion 适配：** ReviewOrchestrator 的审查 prompt 应包含相同的反模式清单（FR-3.5）。

### 2. 前缀缓存共享

审查代理继承父代理的系统 prompt，字节级一致，API 请求直接命中前缀缓存，降低约 26% 成本。

**Axion 适配：** AxionRuntime 创建审查 agent 时复用 buildFullSystemPrompt() 的结果。Swift 没有线程级缓存共享的概念，但同一进程内共享字符串引用是零成本的。

### 3. 工具白名单隔离

审查代理只能操作 memory 和 skill，不能执行代码、写文件、上网。

**Axion 适配：** 审查 agent 通过 AgentOptions.allowedTools 限制工具集。

### 4. 可逆性优先

技能从不自动删除，只归档。

**Axion 适配：** IntelligentCurator 已遵循此原则。

### 5. 技能优先修补而非创建

更新已有技能 > 创建新技能。防止技能库无限膨胀。

**Axion 适配：** LLMSkillEvolver 的审查 prompt 应包含相同的优先级顺序。

## Hermes TG 安全模型详解

来源：`gateway/run.py:_is_user_authorized()`

认证链（按优先级）：
1. `TELEGRAM_ALLOW_ALL_USERS=true` → 全部放行
2. `TELEGRAM_ALLOWED_USERS=12345,67890` → 用户 ID 白名单
3. `TELEGRAM_GROUP_ALLOWED_CHATS=-100xxx` → 群组 chat ID 白名单
4. `GATEWAY_ALLOW_ALL_USERS=true` → 全局放行
5. 默认：拒绝

**Axion MVP 简化：**
- `AXION_TELEGRAM_BOT_TOKEN` — bot token（必填）
- `AXION_TELEGRAM_ALLOWED_USERS` — 单用户 ID（Nick 的 TG user ID）
- 不需要群组支持、不需要全局开关

## Telegram Bot API 长轮询方案

MVP 使用 HTTP 长轮询（getUpdates），不使用 Webhook：

**优势：**
- 无需公网 IP
- 无需 HTTPS 证书
- 无需配置 Webhook URL
- 开发调试简单

**劣势：**
- 延迟比 Webhook 高（轮询间隔通常 1-3 秒）
- 需要管理 offset（防止重复消息）

**实现方式：**
- URLSession HTTP 请求，无需第三方 Swift TG 库
- getUpdates?offset=N&timeout=30（长轮询，30 秒超时）
- sendMessage / sendPhoto / sendDocument 回复

## ReviewHandler 当前状态

当前 `ReviewHandler` 是 stub 实现：

```swift
// ReviewHandler.swift - 当前只检查 + 打日志，不执行审查
func handle(_ event: any AgentEvent, context: EventHandlerContext) async {
    let (doMemory, doSkill) = orchestrator.shouldReview(...)
    if doMemory || doSkill {
        fputs("[axion] review handler: review scheduled\n", stderr)
        // 没有实际执行审查的代码
    }
}
```

Gateway 需要：
1. 在 ReviewHandler 中增加审查执行逻辑（通过 AxionRuntime 创建审查 agent）
2. 或者由 CuratorScheduler 在 run 完成后检查并触发

## CuratorCommand 已有功能

`CuratorCommand` 已提供：
- `axion curator run [--dry-run]` — 立即执行策展
- `axion curator status` — 查看 curator 状态

Gateway 不需要重新实现这些 CLI 命令，只需要 CuratorScheduler 在后台自动调用 IntelligentCurator。
