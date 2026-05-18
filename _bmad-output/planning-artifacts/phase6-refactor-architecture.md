# Phase 6 重构架构对比

## 重构前（现状）

```mermaid
graph TB
    subgraph CLI["CLI 入口"]
        RC["RunCommand.run()"]
    end

    subgraph API["HTTP API 入口"]
        AR["AgentRunner.runAgent()"]
        ARS["AgentRunner.runSkillAgent()"]
    end

    subgraph 死代码["自建 Agent Loop（从未使用）"]
        RE["RunEngine"]
        LP["LLMPlanner"]
        SE["StepExecutor"]
        TV["TaskVerifier"]
        PP["PlanParser"]
    end

    subgraph 共同问题["应用层越权逻辑"]
        SP["手动构建 system prompt<br/>（用 skill.promptTemplate）"]
        AT["手动设置 allowedTools"]
        MCP["无条件传 MCP servers"]
        NSR["不传 skillRegistry<br/>→ restrictionStack = nil"]
    end

    RC --> SP
    RC --> AT
    RC --> MCP
    RC --> NSR
    RC --> SDK["SDK Agent<br/>agent.stream()"]

    AR --> SP
    AR --> AT
    AR --> MCP
    AR --> NSR
    AR --> SDK

    ARS --> SP
    ARS --> AT
    ARS --> MCP
    ARS --> NSR
    ARS --> SDK

    RE --> LP
    RE --> SE
    RE --> TV
    LP --> PP

    style 死代码 fill:#ffcccc,stroke:#cc0000
    style 共同问题 fill:#fff3cd,stroke:#cc9900
```

### 重构前问题清单

| # | 问题 | 位置 |
|---|---|---|
| 1 | RunCommand 和 AgentRunner 各 ~300 行重复代码 | RunCommand.swift / AgentRunner.swift |
| 2 | AgentRunner.runSkillAgent() 复制第三遍 | AgentRunner.swift:276-468 |
| 3 | Skill prompt 由应用层手动构建 | RunCommand:189-214, AgentRunner:301-333 |
| 4 | allowedTools 由应用层手动设置（过滤不生效） | RunCommand:243-246, AgentRunner:343-346 |
| 5 | 不传 skillRegistry → SDK 的 restrictionStack 永远 nil | RunCommand:254, AgentRunner:120/348 |
| 6 | Agent 名称与 SDK Agent 类冲突 | AgentRunner |
| 7 | RunEngine 全套死代码（11+ 文件） | Engine/ Executor/ Planner/ Verifier/ Output/ |
| 8 | runAgent() 不传 tools，SDK 没有注册任何工具 | AgentRunner:120-132 |

---

## 重构后

```mermaid
graph TB
    subgraph 应用层["应用层（薄层 — 只处理输入输出差异）"]
        RC["RunCommand<br/>CLI 参数解析 + TakeoverIO + 终端输出"]
        APR["ApiRunner<br/>HTTP 请求解析 + SSE 推送 + CostTracking + SeatMonitor"]
    end

    subgraph 共享函数["共享 Agent 构建层"]
        BAA["buildAndRunAgent()"]
        SRS["Skill 预解析<br/>resolveExplicitSkill()"]
        HOOK["SafetyHook<br/>（shared seat mode 前台工具阻止）"]
        MEM["MemoryContextProvider<br/>FactStore（记忆注入 system prompt）"]
    end

    subgraph SDK["OpenAgentSDK"]
        AO["AgentOptions<br/>✓ skillRegistry<br/>✓ tools (core + specialist)<br/>✓ mcpServers<br/>✓ hookRegistry (SafetyHook)<br/>✗ 不设 allowedTools"]
        AG["Agent<br/>agent.stream()"]
        SK["SkillTool<br/>+ ToolRestrictionStack"]
        TE["ToolExecutor<br/>restrictionStack 过滤"]
        MCP["MCPClientManager<br/>axion-helper / playwright"]
    end

    RC -->|"CLI flags + task"| BAA
    APR -->|"HTTP params + task"| BAA

    BAA --> SRS
    BAA --> HOOK
    BAA --> MEM
    SRS -->|"/skill-name → user message"| AG
    HOOK --> AO
    MEM --> AO
    BAA --> AO
    AO --> AG
    AG --> SK
    AG --> TE
    AG --> MCP

    style 应用层 fill:#d4edda,stroke:#28a745
    style 共享函数 fill:#cce5ff,stroke:#007bff
    style SDK fill:#e2e3e5,stroke:#6c757d
```

### 重构后职责划分

| 层 | 职责 | 不做什么 |
|---|---|---|
| **RunCommand** | CLI 参数解析、终端输出、TakeoverIO | 不构建 AgentOptions、不处理 skill prompt、不做 SafetyHook/Memory |
| **ApiRunner** | HTTP 请求解析、SSE 推送、结果持久化、CostTracking、SeatMonitor | 不构建 AgentOptions、不处理 skill prompt、不做 SafetyHook/Memory |
| **buildAndRunAgent()** | 加载配置、注册 skill、SafetyHook、Memory 注入、构建 AgentOptions、调 agent.stream() | 不做输出格式化（交给调用方） |
| **resolveExplicitSkill()** | 预解析 /skill-name、格式化为 user message | 不改 system prompt、不设 allowedTools |
| **SDK** | Agent loop、工具执行、Skill 生命周期、restrictionStack 过滤 | — |

### 重构后数据流

```
用户输入: "axion run /polyv-live-cli 获取频道信息"
         │
         ▼
┌─ RunCommand ──────────────────────────────┐
│ 1. 解析 CLI 参数                           │
│ 2. 调用 resolveExplicitSkill()            │
│    → 预解析 skill，生成 user message       │
│ 3. 调用 buildAndRunAgent(config, task, options) │
│ 4. 处理 stream 输出 → 终端打印             │
└───────────────────────────────────────────┘
         │
         ▼
┌─ buildAndRunAgent() ──────────────────────┐
│ 1. 加载配置、解析 API key                  │
│ 2. 注册 SkillRegistry                     │
│ 3. 构建 SafetyHook（shared seat mode）    │
│ 4. 加载 Memory 上下文注入 system prompt    │
│ 5. 构建 AgentOptions:                     │
│    - skillRegistry: registry   ✓          │
│    - tools: core + specialist  ✓          │
│    - mcpServers: {helper, pw}  ✓          │
│    - hookRegistry: SafetyHook  ✓          │
│    - allowedTools: nil         ✓(不设)     │
│ 6. createAgent(options)                   │
│ 7. 返回 agent + stream                    │
└───────────────────────────────────────────┘
         │
         ▼
┌─ SDK Agent Loop ──────────────────────────┐
│ 1. LLM 收到 user message（含 skill 预解析）│
│ 2. LLM 调用 SkillTool（如需）              │
│    → ToolRestrictionStack.push(["bash"])   │
│ 3. ToolExecutor 过滤：只允许 Bash          │
│ 4. LLM 调用 Bash → npx polyv-live-cli     │
│ 5. 返回结果                                │
└───────────────────────────────────────────┘
```
