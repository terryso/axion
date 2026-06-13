---
title: 'MCP Server 用户可配置化'
type: 'feature'
created: '2026-06-13'
status: 'done'
baseline_commit: '178931d'
context:
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Axion 当前 MCP server 列表由 `MCPConfigResolver` 硬编码，只能加载内置 `axion-helper` 和自动探测的 `playwright`。用户无法通过 `~/.axion/config.json` 添加第三方 MCP server，也不能自定义 Playwright MCP 的启动参数。

**Approach:** 在 CLI 层为 `AxionConfig` 增加可解码的 `mcpServers` 字段，使用 Axion 自有 Codable 包装类型承接 `stdio`/`sse`/`http` 三种用户配置，再在 `MCPConfigResolver` 中映射为 SDK 的 `McpServerConfig` 并与内置 server 合并。

## Boundaries & Constraints

**Always:**
- `axion-helper` 永远由 `HelperPathResolver` 解析并内置，用户配置中的同名 key 必须被忽略并输出 stderr warning。
- 缺少 `mcpServers` 字段时行为必须与现状一致：helper 始终存在，`includePlaywright=true` 时继续自动探测 Playwright。
- `mcpServers` 任一 server 解码失败时，整个字段降级为 `nil`，保留其余 AxionConfig 字段并输出 stderr warning。
- 用户显式提供 `playwright` 时必须跳过自动探测；只有 `stdio` 类型有效，非 `stdio` 时 warning 且不启用 Playwright。
- `buildSkillAgent()` 的 `mcpServers: nil` 语义保持不变，skill 执行不加载用户 MCP 配置。

**Ask First:**
- 如果实现需要修改 SDK 的 `McpServerConfig` / `McpStdioConfig` / `McpTransportConfig` 类型契约。
- 如果发现 SDK 当前类型已经支持 Codable，导致包装类型方案不再必要。

**Never:**
- 不新增 CLI flag 或环境变量作为 MCP 配置入口。
- 不实现热重载、profile、registry、单 server 精细降级或 helper 覆盖。
- 不在 `dryrun` 模式下加载任何 MCP server。
- 不改 `axion mcp` 作为 MCP server 暴露给外部客户端的协议面；本需求只改 Axion 作为 MCP client 连接外部 server 的配置。

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|---------------|----------------------------|----------------|
| 无 mcpServers | config.json 不含该字段 | 行为与改造前一致：helper + 自动 Playwright（取决于 includePlaywright） | N/A |
| 合法 stdio server | `{"mcpServers":{"my-server":{"type":"stdio","command":"node","args":["x.js"]}}}` | resolver 返回 `my-server` stdio 配置并透传给 AgentOptions | server 启动失败沿用 SDK 路径 |
| 合法 sse/http server | `type` 为 `sse` 或 `http`，含 `url` | resolver 返回对应远程 MCP 配置 | SDK 连接失败沿用现有路径 |
| 自定义 Playwright | 用户配置 key 为 `playwright` 且类型为 `stdio` | 使用用户配置，跳过 nvm 探测 | N/A |
| Playwright 类型错误 | 用户配置 key 为 `playwright` 但类型为 `sse`/`http` | 不启用 Playwright，也不回退自动探测 | stderr warning |
| 保留 key 冲突 | 用户配置 key 为 `axion-helper` | 忽略用户值，继续使用内置 helperPath | stderr warning |
| mcpServers 解码失败 | 任一 server 缺字段、字段类型错或未知 `type` | `config.mcpServers == nil`，其余配置字段保留 | stderr warning，不阻塞启动 |
| dryrun | `BuildConfig.dryrun == true` | `AgentOptions.mcpServers == nil` | N/A |
| API/MCP server 入口 | `forAPI` 或 `forMCP` 经 `build()` 构造 | 用户配置的非 Playwright MCP server 生效；Playwright 自动探测仍由 includePlaywright 控制 | N/A |
| skill 执行 | `buildSkillAgent()` | 用户 MCP 配置不生效 | N/A |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Config/AxionConfig.swift` -- 当前 Codable 配置模型；需要新增 `mcpServers` 字段、默认值、init 参数、CodingKeys 和局部降级解码。
- `Sources/AxionCLI/Models/AxionMcpServerConfig.swift` -- 新增用户配置包装类型；手写扁平 `{type,...}` Codable，并提供 SDK mapper。
- `Sources/AxionCLI/Services/MCPConfigResolver.swift` -- 当前硬编码 helper/playwright；需要合并用户 server、保护保留 key、处理 Playwright 覆盖。
- `Sources/AxionCLI/Services/AgentBuilder.swift` -- `build()` 第 6 步创建 AgentOptions.mcpServers；需要传入 `config.mcpServers`，dryrun 和 `buildSkillAgent()` 保持 nil。
- `Sources/AxionCLI/Services/AgentBuilder+Config.swift` -- 确认 `includePlaywright` 入口语义：CLI/chat 为 true，API/MCP/skill 为 false。
- `/Users/nick/CascadeProjects/open-agent-sdk-swift/Sources/OpenAgentSDK/Types/MCPConfig.swift` -- SDK MCP 类型来源；当前 `McpServerConfig` 仅 `Sendable`/`Equatable`，不是 Codable。
- `Tests/AxionCLITests/Config/AxionConfigTests.swift` -- 增补 config 局部解码和 round-trip 覆盖。
- `Tests/AxionCLITests/Models/AxionMcpServerConfigTests.swift` -- 新增包装类型 Codable 测试。
- `Tests/AxionCLITests/Services/MCPConfigResolverTests.swift` -- 新增 resolver 合并矩阵测试。
- `README.md` 或 `docs/` -- 增补 `mcpServers` config.json 示例。

## Tasks & Acceptance

**Execution:**
- [x] `Sources/AxionCLI/Models/AxionMcpServerConfig.swift` -- 新建 `AxionMcpServerConfig` enum，支持 `stdio(command,args,env)`、`sse(url)`、`http(url)`，手写扁平 Codable 与 `toSdkConfig()` mapper。
- [x] `Sources/AxionCLI/Config/AxionConfig.swift` -- 新增 `mcpServers: [String: AxionMcpServerConfig]?`，在默认值和 init 中置 nil，在 `init(from:)` 中对该字段单独 do/catch 降级并 warning。
- [x] `Sources/AxionCLI/Services/MCPConfigResolver.swift` -- 新增 `userServers` 参数，按 helper、Playwright、其余用户 server 的顺序合并；保留旧调用的默认参数兼容；跳过会破坏 SDK MCP namespace 的非法 server name。
- [x] `Sources/AxionCLI/Services/AgentBuilder.swift` -- `build()` 调 resolver 时传 `config.mcpServers`；确认 `dryrun` 仍直接 nil、`buildSkillAgent()` 不改。
- [x] `Tests/AxionCLITests/Models/AxionMcpServerConfigTests.swift` -- 覆盖 stdio/sse/http 编解码、args/env 缺省、未知 type 抛错。
- [x] `Tests/AxionCLITests/Config/AxionConfigTests.swift` -- 覆盖无字段、合法字段、坏字段降级且保留其他 config。
- [x] `Tests/AxionCLITests/Services/MCPConfigResolverTests.swift` -- 覆盖保留 key、Playwright 覆盖、Playwright 非 stdio、用户 server 透传、非法 server name、无 userServers 回归。
- [x] `README.md` 或 `docs/` -- 添加 config.json `mcpServers` 示例，说明 `axion-helper` 保留和 Playwright 覆盖语义。

**Acceptance Criteria:**
- Given 用户配置合法 `mcpServers.my-server`，when `AgentBuilder.build()` 走非 dryrun，then `AgentOptions.mcpServers` 包含 helper 与 `my-server`。
- Given 用户配置合法 `mcpServers.playwright` stdio，when resolver 合并，then 返回用户 Playwright 配置且不会调用自动探测结果。
- Given 用户配置 `axion-helper`，when resolver 合并，then 内置 helperPath 优先且 stderr 有 warning。
- Given `mcpServers` 内任一 server 解码失败，when 解码 AxionConfig，then `mcpServers` 为 nil 且其他字段仍按输入/默认值保留。
- Given `buildSkillAgent()`，when config 含用户 MCP server，then skill agent options 仍不加载 MCP server。

## Spec Change Log

## Design Notes

SDK `McpServerConfig` 不应直接放进 `AxionConfig`：它不是 Codable，且包含 `sdk` actor transport，不适合用户声明式 JSON。Axion 包装类型只暴露社区常见的三种外部 transport，避免把 SDK 内部 case 变成配置契约。

用户配置采用 Claude Desktop/Cursor 常见的扁平格式，不能依赖 Swift associated-value enum 的默认 Codable：

```json
{
  "mcpServers": {
    "linear": { "type": "stdio", "command": "npx", "args": ["-y", "@linear/mcp"] },
    "docs": { "type": "sse", "url": "http://localhost:8080/sse" }
  }
}
```

## Verification

**Commands:**
- `swift build` -- expected: 编译通过。
- `swift test --filter "AxionMcpServerConfigTests"` -- expected: 新包装类型 Codable 测试通过。
- `swift test --filter "MCPConfigResolver" --filter "AxionConfig"` -- expected: resolver 合并矩阵与配置解码回归通过。
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` -- expected: 单元测试集合通过；不运行 Integration/AxionE2ETests。

## Suggested Review Order

**Entry Point**

- Start where runtime MCP server assembly now receives user config.
  [`AgentBuilder.swift:118`](../../Sources/AxionCLI/Services/AgentBuilder.swift#L118)

**Config Contract**

- New user-facing config field lives on the persisted AxionConfig model.
  [`AxionConfig.swift:107`](../../Sources/AxionCLI/Config/AxionConfig.swift#L107)

- Partial decode isolates bad mcpServers without losing other config.
  [`AxionConfig.swift:273`](../../Sources/AxionCLI/Config/AxionConfig.swift#L273)

- Wrapper encodes the flat `{type,...}` MCP JSON shape.
  [`AxionMcpServerConfig.swift:35`](../../Sources/AxionCLI/Models/AxionMcpServerConfig.swift#L35)

**Resolver Semantics**

- Helper, Playwright override, and user server merge rules are centralized.
  [`MCPConfigResolver.swift:14`](../../Sources/AxionCLI/Services/MCPConfigResolver.swift#L14)

- Invalid server names are skipped before SDK namespace construction.
  [`MCPConfigResolver.swift:43`](../../Sources/AxionCLI/Services/MCPConfigResolver.swift#L43)

**Tests And Docs**

- Resolver matrix covers reserved keys, Playwright, remote servers, and invalid names.
  [`MCPConfigResolverTests.swift:19`](../../Tests/AxionCLITests/Services/MCPConfigResolverTests.swift#L19)

- Config tests cover absent, valid, bad, and round-trip mcpServers.
  [`AxionConfigTests.swift:389`](../../Tests/AxionCLITests/Config/AxionConfigTests.swift#L389)

- Codable tests pin the flat JSON contract.
  [`AxionMcpServerConfigTests.swift:11`](../../Tests/AxionCLITests/Models/AxionMcpServerConfigTests.swift#L11)

- README shows `~/.axion/config.json` and custom MCP examples.
  [`README.md:483`](../../README.md#L483)
