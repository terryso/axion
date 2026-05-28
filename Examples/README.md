# Examples Tutorial

[中文版](./README_CN.md)

Complete runnable examples demonstrating Open Agent SDK features. Each example is a standalone Swift executable you can run with a single command.

## Prerequisites

- **Swift 6.1+** and **macOS 13+**
- **API Key** — set one of the following environment variables:

```bash
# Option 1: OpenAI-compatible API (GLM, Ollama, OpenRouter, etc.) — default
export CODEANY_API_KEY=your-key
export CODEANY_BASE_URL=https://open.bigmodel.cn/api/coding/paas/v4
export CODEANY_MODEL=glm-5.1

# Option 2: Anthropic API (Claude models)
export ANTHROPIC_API_KEY=sk-ant-...
```

> **Tip:** Add the `export` lines to your `~/.zshrc` or `~/.bashrc` so they persist across sessions. Or copy `.env` from the project root and adjust the values.

## Quick Start

```bash
# 1. Clone and enter the project
git clone https://github.com/terryso/open-agent-sdk-swift.git
cd open-agent-sdk-swift

# 2. Build the project (first time only — resolves all dependencies)
swift build

# 3. Run your first example
swift run BasicAgent
```

That's it! The agent will send a prompt to the LLM and print the response.

## All Examples

### 1. BasicAgent — Agent Creation & Simple Query

The simplest example. Creates an agent, sends a blocking prompt, and prints the response with usage stats.

```bash
swift run BasicAgent
```

**What you'll learn:**
- Creating an agent with `createAgent(options:)`
- Blocking query with `agent.prompt()`
- Reading `QueryResult` fields (text, status, turns, cost, tokens)
- Using Anthropic vs OpenAI-compatible providers

**Key code:**
```swift
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    model: "claude-sonnet-4-6",
    systemPrompt: "You are a helpful assistant.",
    permissionMode: .bypassPermissions
))
let result = await agent.prompt("Explain what an AI agent is in one paragraph.")
```

---

### 2. StreamingAgent — Real-Time Streaming Responses

Shows how to consume agent responses in real-time using `AsyncStream<SDKMessage>`.

```bash
swift run StreamingAgent
```

**What you'll learn:**
- Streaming with `agent.stream()`
- Event types: `partialMessage`, `toolUse`, `toolResult`, `result`, `system`
- Budget tracking with `maxBudgetUsd`

**Key code:**
```swift
for await message in agent.stream("Write a haiku about programming.") {
    switch message {
    case .partialMessage(let data): print(data.text, terminator: "")
    case .result(let data): print("Done: \(data.numTurns) turns, $\(data.totalCostUsd)")
    default: break
    }
}
```

---

### 3. CustomTools — Defining Custom Tools

Demonstrates `defineTool()` with Codable input types, String vs `ToolExecuteResult` returns, and permission control.

```bash
swift run CustomTools
```

**What you'll learn:**
- Creating tools with `defineTool()` and Codable input structs
- JSON Schema definitions for tool parameters
- String return vs `ToolExecuteResult` (success/error) return types
- Read-only tools with `isReadOnly: true`
- Three permission control approaches: closure, Policy, and mode

**Key code:**
```swift
struct WeatherInput: Codable { let city: String }

let weatherTool = defineTool(
    name: "get_weather",
    description: "Get the current weather for a city",
    inputSchema: [...]
) { (input: WeatherInput, context: ToolContext) -> String in
    return "Weather in \(input.city): 22C, sunny"
}
```

---

### 4. CustomSystemPromptExample — Specialized Agent Roles

Shows how to customize agent behavior through system prompts. Creates a "code review expert" agent.

```bash
swift run CustomSystemPromptExample
```

**What you'll learn:**
- Using `systemPrompt` to define agent persona and output format
- How system prompts shape response style and structure
- Running a domain-specific agent (code reviewer)

---

### 5. PromptAPIExample — Blocking API with Built-in Tools

Demonstrates `agent.prompt()` with all 10 core tools registered. The agent autonomously executes tools and returns the final result.

```bash
swift run PromptAPIExample
```

**What you'll learn:**
- Using `getAllBaseTools(tier: .core)` to register all core tools
- Blocking API where the agent uses tools autonomously
- Handling `QueryResult` status and error cases

**Key code:**
```swift
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    tools: getAllBaseTools(tier: .core)
))
let result = await agent.prompt("Analyze the project structure...")
```

---

### 6. MultiToolExample — Multi-Tool Orchestration (Streaming)

Shows an agent autonomously coordinating multiple tools (Glob, Bash, Read) using the streaming API.

```bash
swift run MultiToolExample
```

**What you'll learn:**
- Streaming with `agent.stream()` while tools execute
- Real-time event handling for tool calls and results
- Agent-driven multi-step task orchestration

---

### 7. SubagentExample — Agent Delegation

Demonstrates the main agent delegating tasks to sub-agents via the `Agent` tool.

```bash
swift run SubagentExample
```

**What you'll learn:**
- Creating a coordinator agent with `createAgentTool()`
- How the main agent spawns Explore-type sub-agents
- Sub-agents use a restricted tool set (Read, Glob, Grep, Bash)
- Results flow back from sub-agent to main agent

**Key code:**
```swift
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    tools: getAllBaseTools(tier: .core) + [createAgentTool()]
))
```

---

### 8. PermissionsExample — Permission Policy Comparison

Runs three agents side-by-side, each with a different permission policy, to demonstrate access control.

```bash
swift run PermissionsExample
```

**What you'll learn:**
- `ToolNameAllowlistPolicy` — allow only specific tool names
- `ReadOnlyPolicy` — allow only `isReadOnly == true` tools
- `bypassPermissions` — unrestricted access (for comparison)
- Bridging policies to callbacks with `canUseTool(policy:)`

---

### 9. MCPIntegration — MCP Server Basics

Introduces MCP (Model Context Protocol) integration with `InProcessMCPServer` and stdio configurations.

```bash
swift run MCPIntegration
```

**What you'll learn:**
- Creating an `InProcessMCPServer` with custom tools
- MCP tool namespacing (`mcp__{serverName}__{toolName}`)
- Using `asConfig()` to generate SDK configuration
- Stdio MCP server configuration for external tool servers

**Key code:**
```swift
let server = InProcessMCPServer(name: "my-tools", version: "1.0.0", tools: [echoTool], cwd: "/tmp")
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    mcpServers: ["my-tools": await server.asConfig()]
))
```

---

### 10. AdvancedMCPExample — Multi-Tool MCP with Error Handling

Advanced MCP example with multiple tools and error handling patterns.

```bash
swift run AdvancedMCPExample
```

**What you'll learn:**
- Registering multiple tools in a single MCP server
- Error handling with `ToolExecuteResult(isError: true)`
- Running multiple queries with the same MCP agent
- Namespace verification (`mcp__utility__get_weather`, etc.)

---

### 11. SessionsAndHooks — Session Persistence & Lifecycle Hooks

Demonstrates session persistence (save/resume conversations) and hook registry for lifecycle events.

```bash
swift run SessionsAndHooks
```

**What you'll learn:**
- `SessionStore` for saving/loading/forking sessions
- `HookRegistry` for pre/post tool execution hooks
- `sessionStart`/`sessionEnd` lifecycle hooks
- Session resume across processes using `sessionId`

**Key code:**
```swift
let sessionStore = SessionStore()
let hookRegistry = HookRegistry()
await hookRegistry.register(.preToolUse, definition: HookDefinition(
    matcher: "Bash",
    handler: { input in return HookOutput(message: "Blocked", block: true) }
))
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    sessionStore: sessionStore,
    sessionId: "my-session",
    hookRegistry: hookRegistry
))
```

---

### 12. SkillsExample — Skills System (Built-in & Custom)

Demonstrates the Skills system — registering built-in skills (commit, review, simplify, debug, test), creating custom skills, and executing skills via the LLM.

```bash
swift run SkillsExample
```

**What you'll learn:**
- Initializing built-in skills via `BuiltInSkills`
- Registering and discovering skills with `SkillRegistry`
- Creating custom skills with `Skill(name:description:promptTemplate:toolRestrictions:)`
- Agent executing skills via `createSkillTool(registry:)`

**Key code:**
```swift
let registry = SkillRegistry()
registry.register(BuiltInSkills.commit)
registry.register(BuiltInSkills.review)

let customSkill = Skill(
    name: "explain", description: "Explain code in detail",
    promptTemplate: "Read the files and explain...", toolRestrictions: [.bash, .read]
)
registry.register(customSkill)

let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    tools: getAllBaseTools(tier: .core) + [createSkillTool(registry: registry)]
))
```

---

### 13. SandboxExample — Sandbox Configuration & Enforcement

Shows how to configure path and command restrictions to control Agent's filesystem and Bash operations.

```bash
swift run SandboxExample
```

**What you'll learn:**
- Configuring `SandboxSettings` with path allowlists/denylists
- Command blacklisting (`deniedCommands`) and whitelisting (`allowedCommands`)
- Path traversal protection and symlink resolution
- Shell metacharacter detection for bypass prevention

**Key code:**
```swift
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    sandbox: SandboxSettings(
        allowedReadPaths: ["/project/"],
        allowedWritePaths: ["/project/src/"],
        deniedCommands: ["rm", "sudo"]
    )
))
```

---

### 14. LoggerExample — Structured Logging System

Demonstrates configurable log levels (none/error/warn/info/debug) and output targets (console/file/custom) for SDK diagnostic events.

```bash
swift run LoggerExample
```

**What you'll learn:**
- Configuring log levels via `AgentOptions.logLevel`
- Output targets: `.console`, `.file(URL)`, `.custom(closure)`
- Structured JSON log format (timestamp, level, module, event, data)
- Zero-overhead verification when `logLevel = .none`

**Key code:**
```swift
Logger.configure(level: .debug, output: .custom { jsonLine in
    print("[SDK LOG] \(jsonLine)")
})
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    logLevel: .debug,
    logOutput: .custom { line in myHandler(line) }
))
```

---

### 15. ModelSwitchingExample — Runtime Model Switching

Shows how to dynamically switch LLM models mid-conversation with per-model cost tracking.

```bash
swift run ModelSwitchingExample
```

**What you'll learn:**
- Switching models with `agent.switchModel()`
- Per-model token usage and cost breakdown in `QueryResult`
- Error handling for invalid model names

**Key code:**
```swift
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey, model: "claude-sonnet-4-6"
))
let result1 = await agent.prompt("Simple question...")

try agent.switchModel("claude-opus-4-6")
let result2 = await agent.prompt("Complex analysis...")
// result2.usage shows separate costs per model
```

---

### 16. QueryAbortExample — Query Cancellation

Demonstrates how to cancel running Agent queries using Swift's `Task.cancel()` and retrieve partial results.

```bash
swift run QueryAbortExample
```

**What you'll learn:**
- Launching queries in Swift `Task` for cancellation support
- Cancelling with `Task.cancel()` or `agent.interrupt()`
- Handling `QueryResult.isCancelled` and partial tool results
- Stream cancellation via `SDKMessage` events

**Key code:**
```swift
let task = Task {
    for await message in agent.stream("Long-running task...") {
        // process events
    }
}
// Cancel after delay
DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
    task.cancel()
}
```

---

### 17. ContextInjectionExample — File Cache & Context Injection

Shows file caching with LRU eviction, Git status auto-injection, and project document discovery (CLAUDE.md/AGENT.md).

```bash
swift run ContextInjectionExample
```

**What you'll learn:**
- Configuring `FileCache` parameters (maxEntries, maxSizeBytes)
- Cache hit/miss statistics and eviction tracking
- Git context collection (`<git-context>` in system prompt)
- Project document discovery (`<project-instructions>` from CLAUDE.md/AGENT.md)
- Cache invalidation on file writes

**Key code:**
```swift
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    projectRoot: "/path/to/project"
))
// System prompt automatically includes <git-context> and <project-instructions>
```

---

### 18. MultiTurnExample — Multi-Turn Conversation with SessionStore

Demonstrates multi-turn conversations with context retention across queries using `SessionStore`.

```bash
swift run MultiTurnExample
```

**What you'll learn:**
- Executing sequential queries on the same Agent instance
- Context retention across turns (Agent remembers earlier messages)
- Inspecting conversation history with `agent.getMessages()`
- Streaming support in multi-turn conversations

**Key code:**
```swift
let sessionStore = SessionStore()
let agent = createAgent(options: AgentOptions(
    apiKey: apiKey,
    sessionStore: sessionStore,
    sessionId: "conversation-1"
))

// Turn 1
let result1 = await agent.prompt("My name is Nick.")
// Turn 2 — Agent remembers the name from turn 1
let result2 = await agent.prompt("What is my name?")
```

---

### 19. OpenAICompatExample — OpenAI-Compatible API Providers

Shows how to use OpenAI-compatible APIs (GLM, DeepSeek, Qwen, Ollama, OpenRouter, etc.) with the same Agent API.

```bash
swift run OpenAICompatExample
```

**What you'll learn:**
- Configuring `provider: .openai` with custom `baseURL`
- Using environment variables (`CODEANY_API_KEY`, `CODEANY_BASE_URL`, `CODEANY_MODEL`)
- Comparing Anthropic vs OpenAI-compatible provider setup
- Running tools with OpenAI-compatible providers

**Key code:**
```swift
let agent = createAgent(options: AgentOptions(
    provider: .openai,
    apiKey: ProcessInfo.processInfo.environment["CODEANY_API_KEY"] ?? "",
    model: "glm-5.1",
    baseURL: "https://open.bigmodel.cn/api/coding/paas/v4",
    permissionMode: .bypassPermissions
))
```

---

## Compat Verification Examples

These 12 examples verify that the Swift SDK's API surface is fully compatible with the [open-agent-sdk-typescript](https://github.com/codeany-ai/open-agent-sdk-typescript). Each example runs a structured compat report comparing TypeScript SDK fields to their Swift equivalents, printing PASS/MISSING status for every field.

> **Note:** Compat examples are verification tools, not typical usage demos. They're useful for SDK maintainers and contributors to track API parity.

### 20. CompatCoreQuery — Core Query API Compat

Verifies Swift SDK's `prompt()`/`stream()` API covers all TypeScript SDK core usage patterns.

```bash
swift run CompatCoreQuery
```

**What you'll learn:**
- TypeScript SDK `query()` vs Swift `prompt()`/`stream()` mapping
- Blocking and streaming query patterns
- `QueryResult` field parity (text, usage, turns, cost, status)

---

### 21. CompatToolSystem — Tool System Compat

Verifies Swift SDK's tool definition and execution matches TypeScript SDK's tool system.

```bash
swift run CompatToolSystem
```

**What you'll learn:**
- `defineTool()` API parity with TypeScript's `tool()` function
- Tool input schema, `ToolContext`, and `ToolExecuteResult` compatibility
- Tool registration and execution lifecycle

---

### 22. CompatMessageTypes — Message Types Compat

Verifies Swift SDK's `SDKMessage` covers all 20 TypeScript SDK message subtypes.

```bash
swift run CompatMessageTypes
```

**What you'll learn:**
- Full `SDKMessage` enum parity (partialMessage, toolUse, toolResult, result, system, etc.)
- Streaming event type coverage
- Message data field mapping

---

### 23. CompatHooks — Hook System Compat

Verifies Swift SDK's hook system supports all 18 TypeScript SDK `HookEvents` with matching Input/Output types.

```bash
swift run CompatHooks
```

**What you'll learn:**
- All lifecycle event types (preToolUse, postToolUse, sessionStart, sessionEnd, etc.)
- `HookDefinition` matcher and handler API parity
- `HookInput`/`HookOutput` field coverage

---

### 24. CompatMCP — MCP Integration Compat

Verifies Swift SDK supports all TypeScript SDK MCP server configuration types and runtime management.

```bash
swift run CompatMCP
```

**What you'll learn:**
- Server config types: stdio, SSE, HTTP, in-process
- `McpStdioConfig`, `McpSseConfig` field parity
- Runtime MCP server lifecycle management

---

### 25. CompatSessions — Session Management Compat

Verifies Swift SDK's session API covers all TypeScript SDK session operations.

```bash
swift run CompatSessions
```

**What you'll learn:**
- `SessionStore` operations: save, load, fork, list, rename, tag, delete
- Session configuration options parity
- Session ID management and auto-restore

---

### 26. CompatQueryMethods — Query Object Methods Compat

Verifies Swift SDK provides all TypeScript SDK Query object runtime control methods.

```bash
swift run CompatQueryMethods
```

**What you'll learn:**
- Runtime controls: abort, interrupt, status check
- Query lifecycle methods mapping
- Partial result retrieval compatibility

---

### 27. CompatOptions — Agent Options Compat

Verifies Swift SDK's `AgentOptions`/`SDKConfiguration` covers all TypeScript SDK Options fields.

```bash
swift run CompatOptions
```

**What you'll learn:**
- All `AgentOptions` fields and their TypeScript equivalents
- Configuration inheritance and defaults
- Environment variable mapping

---

### 28. CompatPermissions — Permission System Compat

Verifies Swift SDK's permission system covers all TypeScript SDK permission types and operations.

```bash
swift run CompatPermissions
```

**What you'll learn:**
- Permission mode parity (bypassPermissions, acceptEdits, default, etc.)
- Custom authorization callback API
- Policy composition compatibility

---

### 29. CompatSubagents — Subagent System Compat

Verifies Swift SDK's subagent system covers TypeScript SDK's `AgentDefinition` and Agent tool usage.

```bash
swift run CompatSubagents
```

**What you'll learn:**
- `createAgentTool()` and agent spawning API parity
- Sub-agent type support (Explore, Plan, etc.)
- Team/task coordination field coverage

---

### 30. CompatThinkingModel — Thinking & Model Config Compat

Verifies Swift SDK's `ThinkingConfig` and model configuration are fully compatible with TypeScript SDK.

```bash
swift run CompatThinkingModel
```

**What you'll learn:**
- `ThinkingConfig` options (budget tokens, type)
- `ModelInfo` fields and model switching parity
- Extended thinking and reasoning control

---

### 31. CompatSandbox — Sandbox Configuration Compat

Verifies Swift SDK's sandbox configuration covers all TypeScript SDK sandbox options.

```bash
swift run CompatSandbox
```

**What you'll learn:**
- `SandboxSettings` full field coverage (paths, commands, network, ripgrep)
- `SandboxNetworkConfig` and `RipgrepConfig` parity
- Path traversal protection and shell filtering options

---

### 32. EventBusExample — Runtime Event Layer (Epic 26)

Demonstrates the EventBus: basic publish/subscribe, type-filtered subscription, multiple concurrent subscribers, and buffering behavior.

```bash
swift run EventBusExample
```

**No API key required** — this example publishes synthetic events.

**What you'll learn:**
- Creating an `EventBus()` and subscribing to all events
- Publishing typed events (`SessionCreatedEvent`, `AgentStartedEvent`, `ToolStartedEvent`, etc.)
- Type-filtered subscription — `bus.subscribe(ToolStartedEvent.self)` receives only that type
- Multiple concurrent subscribers (CLI logger, cost monitor, tool tracer)
- Buffer policy: `.bufferingNewest(100)` — slow consumers don't block publishers

**Key code:**
```swift
let bus = EventBus()

// Subscribe to all events
let (subId, stream) = await bus.subscribe()

// Subscribe to specific type only
let toolStream = bus.subscribe(ToolStartedEvent.self)

// Publish events
await bus.publish(SessionCreatedEvent(sessionId: "sess-001", task: "Analyze", model: "claude-sonnet-4-6"))
await bus.publish(ToolStartedEvent(sessionId: "sess-001", toolName: "Read", toolUseId: "tu_01", input: "/data/file.csv"))

// Unsubscribe
await bus.unsubscribe(subId)
```

---

### 33. SSEBridgeExample — EventBus to SSE Pipeline (Epic 28)

Demonstrates the full SSE bridge pipeline: `EventBus → EventBusBridge → EventBroadcaster → SSE stream`. Also shows real-time token streaming via `LLMTokenStreamEvent`.

```bash
swift run SSEBridgeExample
```

**Requires API key** — set `CODEANY_API_KEY` or `ANTHROPIC_API_KEY`.

**What you'll learn:**
- Building the SSE pipeline: `EventBusBridge(eventBus:broadcaster:runId:)`
- Passing `eventBus` and `emitTokenStream` to `AgentOptions`
- Subscribing to raw EventBus events and SSE events in parallel
- Using `EventBroadcaster.getReplayBuffer()` for disconnected client catch-up
- `AgentSSEEvent.encodeToSSE()` for SSE wire format

**Key code:**
```swift
let eventBus = EventBus()
let broadcaster = EventBroadcaster()
let bridge = EventBusBridge(eventBus: eventBus, broadcaster: broadcaster, runId: "run-1")
await bridge.start()

// Create agent with EventBus + token streaming
let agent = createAgent(options: AgentOptions(
    apiKey: "sk-...",
    eventBus: eventBus,
    emitTokenStream: true
))
```

## Example Dependencies

| Example                  | Requires MCP dependency | Extra setup              |
| ------------------------ | ---------------------- | ------------------------ |
| BasicAgent               | No                     | None                     |
| StreamingAgent           | No                     | None                     |
| CustomTools              | No                     | None                     |
| CustomSystemPrompt       | No                     | None                     |
| PromptAPIExample         | No                     | None                     |
| MultiToolExample         | No                     | None                     |
| SubagentExample          | No                     | None                     |
| PermissionsExample       | No                     | None                     |
| MCPIntegration           | Yes (`import MCP`)     | None                     |
| AdvancedMCPExample       | Yes (`import MCP`)     | None                     |
| SessionsAndHooks         | No                     | None                     |
| SkillsExample            | No                     | None                     |
| SandboxExample           | No                     | None                     |
| LoggerExample            | No                     | None                     |
| ModelSwitchingExample    | No                     | None                     |
| QueryAbortExample        | No                     | None                     |
| ContextInjectionExample  | No                     | None                     |
| MultiTurnExample         | No                     | None                     |
| OpenAICompatExample      | No                     | None                     |
| PolyvLiveExample         | No                     | Skill directory with SKILL.md |
| CompatCoreQuery          | No                     | None                     |
| CompatToolSystem         | No                     | None                     |
| CompatMessageTypes       | No                     | None                     |
| CompatHooks              | No                     | None                     |
| CompatMCP                | No                     | None                     |
| CompatSessions           | No                     | None                     |
| CompatQueryMethods       | No                     | None                     |
| CompatOptions            | No                     | None                     |
| CompatPermissions        | No                     | None                     |
| CompatSubagents          | No                     | None                     |
| CompatThinkingModel      | No                     | None                     |
| CompatSandbox            | No                     | None                     |
| EventBusExample          | No                     | None (synthetic events)  |
| SSEBridgeExample         | No                     | API key required         |

All examples are defined as executable targets in `Package.swift` — no additional configuration needed.

## Core Scenario Quick Index

Five essential scenarios every developer should understand. Each links to the relevant example(s):

| # | Core Scenario | Example(s) | Quick Run |
|---|--------------|-----------|-----------|
| 1 | **Basic Agent** — create, prompt, stream | `BasicAgent/`, `StreamingAgent/` | `swift run BasicAgent` |
| 2 | **Custom Tools** — defineTool, Codable input | `CustomTools/`, `MultiToolExample/` | `swift run CustomTools` |
| 3 | **MCP Integration** — external tool servers | `MCPIntegration/`, `AdvancedMCPExample/`, `AgentMCPServerExample/` | `swift run MCPIntegration` |
| 4 | **Session Management** — save, load, fork | `CompatSessions/`, `SessionsAndHooks/`, `MultiTurnExample/` | `swift run SessionsAndHooks` |
| 5 | **Memory (Cross-Task Learning)** — store, query, domain-based | `MemoryStoreExample/` | `swift run MemoryStoreExample` |
| 6 | **Self-Evolution** — experience extraction, skill evolution, curation | `SelfEvolutionExample/` | `swift run SelfEvolutionExample` |
| 7 | **Runtime Events** — EventBus, typed events, SSE bridge | `EventBusExample/`, `SSEBridgeExample/` | `swift run EventBusExample` |

> **Tip:** Start with scenario 1 (BasicAgent), then explore each scenario in order. The full learning path below covers all 33 examples.

## Recommended Learning Path

```
BasicAgent → StreamingAgent → CustomTools → CustomSystemPromptExample
    → PromptAPIExample → MultiToolExample → SubagentExample
    → PermissionsExample → MCPIntegration → AdvancedMCPExample
    → SessionsAndHooks → SkillsExample → SandboxExample
    → LoggerExample → ModelSwitchingExample → QueryAbortExample
    → ContextInjectionExample → MultiTurnExample → OpenAICompatExample
    → PolyvLiveExample → EventBusExample → SSEBridgeExample
```

1. **Start here:** BasicAgent, StreamingAgent — understand the core prompt/stream APIs
2. **Add tools:** CustomTools, CustomSystemPromptExample — learn tool definition and prompt customization
3. **Use built-in tools:** PromptAPIExample, MultiToolExample — see agents autonomously use tools
4. **Multi-agent:** SubagentExample — delegate tasks to sub-agents
5. **Security:** PermissionsExample — control what tools agents can use
6. **MCP integration:** MCPIntegration, AdvancedMCPExample — connect external tool servers
7. **Persistence:** SessionsAndHooks — save sessions and hook into lifecycle events
8. **Skills:** SkillsExample, PolyvLiveExample — register and execute built-in/custom skills, use SKILL.md auto-discovery
9. **Sandbox & Logging:** SandboxExample, LoggerExample — restrict operations and capture logs
10. **Advanced controls:** ModelSwitchingExample, QueryAbortExample — runtime model switching and query cancellation
11. **Context & multi-turn:** ContextInjectionExample, MultiTurnExample — file caching, context injection, multi-turn conversations
12. **OpenAI compat:** OpenAICompatExample — use DeepSeek, Qwen, Ollama, and other OpenAI-compatible APIs
13. **HTTP API Server:** AgentHTTPServerExample — expose an Agent as a REST + SSE HTTP service
14. **SDK compat verification:** Compat* examples — verify TypeScript SDK API parity (for SDK contributors)
15. **Runtime events:** EventBusExample, SSEBridgeExample — EventBus publish/subscribe, SSE bridge pipeline, token streaming

## Troubleshooting

### Build errors

```bash
# Clean and rebuild
swift package clean
swift build
```

### "No such module 'OpenAgentSDK'"

Make sure you're running from the project root directory where `Package.swift` is located.

### API key errors

Check that your environment variable is set:

```bash
echo $ANTHROPIC_API_KEY   # should print your key
# or
echo $CODEANY_API_KEY
```

### Running in Xcode

```bash
open Package.swift
```

Then select any example target from the scheme selector and press Cmd+R to run.

### Using with GLM / other OpenAI-compatible providers

The examples default to `ANTHROPIC_API_KEY`, but you can modify them to use any OpenAI-compatible provider:

```swift
let agent = createAgent(options: AgentOptions(
    apiKey: ProcessInfo.processInfo.environment["CODEANY_API_KEY"] ?? "your-key",
    model: "glm-5.1",
    baseURL: "https://open.bigmodel.cn/api/coding/paas/v4",
    provider: .openai,
    permissionMode: .bypassPermissions
))
```
