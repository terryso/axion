# Session 持久化与跨任务记忆指南

OpenAgentSDK 提供两种持久化机制：**Session**（对话历史保存与恢复）和 **MemoryStore**（跨任务知识积累）。

---

## 1. Session 持久化

### 1.1 消息流与基本用法

Agent 提供 `agent.prompt()`（阻塞）和 `agent.stream()`（流式）两种调用。每次调用：构建消息 -> 发送 LLM -> 执行工具 -> 重复直到结束 -> 自动保存到 SessionStore。

```swift
let agent = createAgent(options: AgentOptions(apiKey: "sk-...", model: "claude-sonnet-4-6"))

let result = await agent.prompt("解释 Swift Actor")  // 阻塞式
for await event in agent.stream("写 HTTP 服务器") {    // 流式
    if case .partialMessage(let d) = event { print(d.text, terminator: "") }
}
```

### 1.2 SessionStore 配置与自动行为

在 `AgentOptions` 中同时设置 `sessionStore` 和 `sessionId` 即可启用：

```swift
let store = SessionStore()  // 默认 ~/.open-agent-sdk/sessions/
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-...", model: "claude-sonnet-4-6",
    sessionStore: store, sessionId: "session-001"
))
```

自动行为：**创建时恢复**历史消息 -> **追加**用户输入 -> **完成后保存**完整对话。

```swift
let r1 = await agent.prompt("项目用 SwiftUI，帮我设计架构")  // 自动保存
let r2 = await agent.prompt("加入网络层怎么设计？")          // 自动恢复+保存
// 第二轮 Agent 记住之前讨论的 SwiftUI 架构
```

### 1.3 多轮对话

```swift
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-...", sessionStore: SessionStore(), sessionId: "proj-alpha"
))
await agent.prompt("创建 User 模型")
await agent.prompt("加上验证逻辑")    // 知道 User 模型
await agent.prompt("写单元测试")      // 知道模型和验证逻辑
```

---

## 2. MemoryStoreProtocol 与 FileBasedMemoryStore

### 2.1 接口定义

```swift
public protocol MemoryStoreProtocol: Sendable {
    func save(domain: String, knowledge: KnowledgeEntry) async throws
    func query(domain: String, filter: KnowledgeQueryFilter?) async throws -> [KnowledgeEntry]
    func delete(domain: String, olderThan: Date) async throws -> Int
    func listDomains() async throws -> [String]
}
```

### 2.2 核心数据类型

```swift
struct KnowledgeEntry: Sendable {
    let id: String; let content: String; let tags: [String]
    let createdAt: Date; let sourceRunId: String?
}

struct KnowledgeQueryFilter: Sendable {
    let tags: [String]?; let olderThan: Date?; let newerThan: Date?; let limit: Int?
}
```

### 2.3 FileBasedMemoryStore

每个域存为一个 JSON 文件，默认 `~/.agent/memory/`，默认过期 30 天：

```swift
let store = FileBasedMemoryStore()                              // 默认
let store = FileBasedMemoryStore(memoryDir: "/custom/path")    // 自定义路径
let store = FileBasedMemoryStore(maxAge: 7 * 24 * 3600)       // 7 天过期
```

### 2.4 注入与工具内访问

```swift
let memoryStore = FileBasedMemoryStore()
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-...", model: "claude-sonnet-4-6", memoryStore: memoryStore
))
// memoryStore 自动注入到 ToolContext，工具内通过 context.memoryStore 访问
```

工具中使用示例：

```swift
struct KInput: Codable { let domain: String; let content: String; let tags: [String] }

let saveTool = defineTool(name: "save_knowledge", description: "保存知识到长期记忆",
    inputSchema: ["type":"object","properties":[
        "domain":["type":"string"],"content":["type":"string"],
        "tags":["type":"array","items":["type":"string"]]
    ],"required":["domain","content"]]
) { (input: KInput, ctx: ToolContext) async throws -> String in
    guard let store = ctx.memoryStore else { return "未配置" }
    try await store.save(domain: input.domain, knowledge: KnowledgeEntry(
        id: UUID().uuidString, content: input.content, tags: input.tags, createdAt: Date()))
    return "已保存到 \(input.domain)"
}
```

---

## 3. 跨任务记忆的读写和使用模式

### 3.1 读写知识

```swift
// 任务前查询相关知识
let entries = try await store.query(domain: "swiftui",
    filter: KnowledgeQueryFilter(tags: ["best-practice"]))

// 任务后记录学到的知识
try await store.save(domain: "swiftui", knowledge: KnowledgeEntry(
    id: UUID().uuidString,
    content: "@State 只能在 View 中使用，@Observable 适合 ViewModel",
    tags: ["state-management", "best-practice"], createdAt: Date()
))
```

### 3.2 按域和标签组织

域是一级分类（按应用/场景），标签是二级分类：

```swift
try await store.save(domain: "xcode", knowledge: xcodeTip)
try await store.save(domain: "git", knowledge: gitWorkflow)
let domains = try await store.listDomains()  // ["git", "xcode"]

// 按标签筛选
let filter = KnowledgeQueryFilter(tags: ["best-practice"])
let results = try await store.query(domain: "swiftui", filter: filter)
```

### 3.3 示例：学习型 Agent

```swift
let ms = FileBasedMemoryStore()

let learnTool = defineTool(name:"learn",description:"记录学到的知识",
    inputSchema:["type":"object","properties":[
        "domain":["type":"string"],"content":["type":"string"],
        "tags":["type":"array","items":["type":"string"]]
    ],"required":["domain","content"]]
) { (input:KInput, ctx:ToolContext) async throws -> String in
    try await ctx.memoryStore!.save(domain:input.domain, knowledge: KnowledgeEntry(
        id:UUID().uuidString, content:input.content, tags:input.tags, createdAt:Date()))
    return "已记录"
}

let recallTool = defineTool(name:"recall",description:"回忆之前的知识",
    inputSchema:["type":"object","properties":[
        "domain":["type":"string"],"tags":["type":"array","items":["type":"string"]]
    ],"required":["domain"]]
) { (input:KInput, ctx:ToolContext) async throws -> String in
    let entries = try await ctx.memoryStore!.query(domain:input.domain,
        filter: KnowledgeQueryFilter(tags: input.tags.isEmpty ? nil : input.tags))
    return entries.map(\.content).joined(separator:"\n---\n")
}

let agent = createAgent(options: AgentOptions(
    apiKey: "sk-...", model: "claude-sonnet-4-6",
    systemPrompt: "完成任务后用 learn 记录，遇到问题时先 recall。",
    memoryStore: ms, tools: [learnTool, recallTool]
))
// 每次运行积累知识，跨实例持久化
```

---

## 4. Session 管理（save/load/fork/list/delete）

### 4.1 SessionStore 操作

`SessionStore` 是基于 Actor 的线程安全存储：

```swift
let store = SessionStore()

// save — 持久化
try await store.save(sessionId: "s1", messages: [
    ["role":"user","content":"你好"], ["role":"assistant","content":"你好！"]
], metadata: PartialSessionMetadata(cwd:"/project", model:"claude-sonnet-4-6", summary:"讨论"))

// load — 恢复（支持分页）
if let data = try await store.load(sessionId: "s1") { print(data.metadata.messageCount) }

// fork — 分支（可选截断到指定消息索引）
if let id = try await store.fork(sourceSessionId:"s1", newSessionId:"s1-exp", upToMessageIndex:3) {
    print("分支: \(id)")
}

// list — 列出会话（按更新时间降序）
for s in try await store.list(limit: 5) { print("[\(s.id)] \(s.summary ?? "-")") }

// delete — 删除
_ = try await store.delete(sessionId: "s1-exp")

// rename / tag
try await store.rename(sessionId: "s1", newTitle: "架构讨论")
try await store.tag(sessionId: "s1", tag: "architecture")
```

### 4.2 AgentOptions 恢复会话

```swift
// 恢复指定会话
let a1 = createAgent(options:AgentOptions(apiKey:"sk-...", sessionStore:store, sessionId:"s1"))

// 继续最近一次会话
let a2 = createAgent(options:AgentOptions(apiKey:"sk-...", sessionStore:store, continueRecentSession:true))

// Fork 后继续
let a3 = createAgent(options:AgentOptions(apiKey:"sk-...", sessionStore:store, sessionId:"s1", forkSession:true))
```

### 4.3 continueRecentSession / forkSession / resumeSessionAt

优先级：`continueRecentSession` -> `forkSession` -> `resumeSessionAt`

```swift
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-...", sessionStore: store,
    continueRecentSession: true,
    resumeSessionAt: "msg-uuid-005"  // 截断到该消息重新开始
))
```

### 4.4 示例：保存、分支、探索、恢复

```swift
let store = SessionStore()

// 1. 创建并保存
let agent = createAgent(options: AgentOptions(
    apiKey:"sk-...", model:"claude-sonnet-4-6", sessionStore:store, sessionId:"design"
))
await agent.prompt("设计用户认证系统架构")  // 自动保存

// 2. Fork 用于探索
if let fid = try await store.fork(sourceSessionId:"design", newSessionId:"design-jwt") {
    let exp = createAgent(options:AgentOptions(
        apiKey:"sk-...", model:"claude-sonnet-4-6", sessionStore:store, sessionId:fid
    ))
    await exp.prompt("改用 JWT 怎么调整？")  // 独立保存，不影响原始会话
}

// 3. 恢复原始会话
let orig = createAgent(options:AgentOptions(
    apiKey:"sk-...", model:"claude-sonnet-4-6", sessionStore:store, sessionId:"design"
))
await orig.prompt("基于之前讨论，写出认证模块代码")

// 4. 临时会话（不自动保存）
let temp = createAgent(options:AgentOptions(
    apiKey:"sk-...", sessionStore:store, sessionId:"temp", persistSession:false
))
```

---

## 总结

| 机制 | 用途 | 生命周期 | 存储位置 |
|------|------|----------|----------|
| **Session** | 对话上下文保持 | 单次会话 | `~/.open-agent-sdk/sessions/` |
| **MemoryStore** | 跨任务知识积累 | 跨会话、跨进程 | `~/.agent/memory/` |

Session 保持短期对话上下文，MemoryStore 积累长期知识，两者结合实现完整的 Agent 记忆系统。
