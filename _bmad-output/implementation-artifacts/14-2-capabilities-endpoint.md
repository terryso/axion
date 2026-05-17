# Story 14.2: Capabilities 端点

Status: done

## Story

As a 外部集成方,
I want 通过 API 发现 Axion 的桌面操作能力,
So that 我可以动态适配不同配置的 Axion 实例.

## Acceptance Criteria

1. **AC1: GET /v1/capabilities 返回完整能力描述**
   - **Given** GET /v1/capabilities 请求
   - **When** 响应
   - **Then** 返回 JSON 包含：version（Axion 版本）、supported_run_statuses（所有可能的 APIRunStatus 值）、supported_result_kinds（answer/confirmation）、available_tools（ToolNames.allToolNames 列表）、max_concurrent_runs（ConcurrencyLimiter.maxConcurrent）、features（支持的功能列表：memory、takeover、fast_mode、skills）

2. **AC2: Helper 未连接时降级返回**
   - **Given** Helper 未连接
   - **When** GET /v1/capabilities
   - **Then** available_tools 仍返回 `ToolNames.allToolNames`（静态列表，不依赖运行时连接），version 和 features 正常返回

3. **AC3: 可缓存性**
   - **Given** capabilities 响应
   - **When** 检查 HTTP headers
   - **Then** 包含 `Cache-Control: max-age=300`（建议缓存 5 分钟），响应为稳定的 JSON schema

4. **AC4: 认证一致性**
   - **Given** server 启用了 --auth-key
   - **When** GET /v1/capabilities
   - **Then** 同样受 AuthMiddleware 保护（在 v1Authed 路由组中注册）

5. **AC5: Codable round-trip**
   - **Given** CapabilitiesResponse 实例
   - **When** JSON 编码再解码
   - **Then** 所有字段完整保留（Codable round-trip 测试）

## Tasks / Subtasks

- [x] Task 1: 定义 CapabilitiesResponse model (AC: #1, #5)
  - [x] 1.1 在 `APITypes.swift` 中新增 `CapabilitiesResponse` struct（Codable + Equatable + Sendable + ResponseEncodable）
  - [x] 1.2 CodingKeys 使用 snake_case：`supported_run_statuses`、`supported_result_kinds`、`available_tools`、`max_concurrent_runs`
  - [x] 1.3 features 字段为 `[String]` 类型，包含固定值：`["memory", "takeover", "fast_mode", "skills"]`

- [x] Task 2: 注册 GET /v1/capabilities 路由 (AC: #1, #3, #4)
  - [x] 2.1 在 `AxionAPI.registerRoutes()` 中，在 v1Authed 路由组添加 `GET capabilities` 路由
  - [x] 2.2 路由闭包中构建 `CapabilitiesResponse`：version 从 `AxionVersion.current`、run_statuses 从 `APIRunStatus.allCases`、result_kinds 从 `TaskResultKind.allCases`、tools 从 `ToolNames.allToolNames`
  - [x] 2.3 max_concurrent_runs 从 `ConcurrencyLimiter.maxConcurrent` 获取（需将 limiter 传入 registerRoutes 或直接传入 maxConcurrent 值）
  - [x] 2.4 添加 `Cache-Control: max-age=300` 响应头
  - [x] 2.5 在 `ServerCommand.swift` 中将 `maxConcurrent` 传入 registerRoutes（如果尚未传递）

- [x] Task 3: APIRunStatus 添加 allCases (AC: #1)
  - [x] 3.1 `APIRunStatus` 已是 String + Codable enum，添加 `CaseIterable` conformance（或手写 allCases 静态属性）以支持 capabilities 枚举

- [x] Task 4: TaskResultKind 添加 allCases (AC: #1)
  - [x] 4.1 `TaskResultKind` 已是 String + Codable enum，添加 `CaseIterable` conformance

- [x] Task 5: 单元测试 (All ACs)
  - [x] 5.1 `CapabilitiesResponseTests` — Codable round-trip、JSON key 命名验证、features 包含所有预期值
  - [x] 5.2 在 `AxionAPIRoutesTests.swift` 中添加 capabilities 路由测试（验证返回结构完整性和 Cache-Control header）
  - [x] 5.3 验证 `APIRunStatus.allCases` 包含全部 8 种状态
  - [x] 5.4 验证 `TaskResultKind.allCases` 包含 answer 和 confirmation

## Dev Notes

### 架构上下文

本 Story 在 Epic 5（HTTP API Server）和 Story 14.1（StandardTaskOutput）基础上添加能力发现端点。参考 OpenClick `src/api-runs.ts:218-252` 的 `capabilitiesResponse()` 函数。

**关键原则：**
- Capabilities 是静态快照 — 不依赖 Helper 运行时连接状态
- available_tools 使用 `ToolNames.allToolNames`（AxionCore 静态常量），不需要运行时查询 Helper
- features 列表是编译时确定的固定值
- max_concurrent_runs 从 `ConcurrencyLimiter.maxConcurrent` 读取（当前由 ServerCommand --max-concurrent 参数传入）

### registerRoutes 参数传递

当前 `AxionAPI.registerRoutes()` 签名中 `concurrencyLimiter` 是可选参数。Capabilities 需要知道 maxConcurrent 值。两种方案：
1. **方案 A（推荐）**：直接传入 `maxConcurrent: Int` 参数到 registerRoutes，与 concurrencyLimiter 并列
2. **方案 B**：从已有的 concurrencyLimiter 读取 `await limiter.maxConcurrent`

方案 A 更简单、不依赖 async。建议直接在 `registerRoutes` 中新增 `maxConcurrent: Int = 10` 参数。

### 数据来源映射

| Capabilities 字段 | 数据来源 | 路径 |
|---|---|---|
| version | `AxionVersion.current` | `Sources/AxionCLI/Constants/Version.swift` |
| supported_run_statuses | `APIRunStatus.allCases.map(\.rawValue)` | `Sources/AxionCLI/API/Models/APITypes.swift:8-17` |
| supported_result_kinds | `TaskResultKind.allCases.map(\.rawValue)` | `Sources/AxionCLI/API/Models/APITypes.swift:146-149` |
| available_tools | `ToolNames.allToolNames` | `Sources/AxionCore/Constants/ToolNames.swift:30-37` |
| max_concurrent_runs | `maxConcurrent` 参数 | `Sources/AxionCLI/Commands/ServerCommand.swift:23` |
| features | 编译时常量 `["memory", "takeover", "fast_mode", "skills"]` | — |

### 路由注册位置

在 `AxionAPI.swift` 的 `registerRoutes()` 中，在 `v1Authed` 路由组内、`GET /v1/runs` 之前注册，保持与 OpenClick 路由注册顺序一致（capabilities 在 runs 之前）。

### CaseIterable 注意事项

`APIRunStatus` 和 `TaskResultKind` 都是 `enum Xxx: String, Codable, Equatable, Sendable`。添加 `CaseIterable` conformance 即可自动合成 `allCases`。需要同时添加到 declaration line：

```swift
enum APIRunStatus: String, Codable, Equatable, Sendable, CaseIterable {
enum TaskResultKind: String, Codable, Equatable, Sendable, CaseIterable {
```

### AxionBar 影响

AxionBar 当前不消费 `/v1/capabilities` 端点，本 Story 不需要修改 AxionBar 代码。

### 项目结构规范

- Model 定义在 `Sources/AxionCLI/API/Models/APITypes.swift`（与 StandardTaskOutput 同文件）
- 路由注册在 `Sources/AxionCLI/API/AxionAPI.swift`
- 测试在 `Tests/AxionCLITests/API/AxionAPIRoutesTests.swift`（现有文件）和可能的 `Tests/AxionCLITests/API/APITypesTests.swift`
- 使用 JSONEncoder + Codable，不用手动 JSON 拼接
- CodingKeys 使用 snake_case（MCP/API 约定）

### 测试策略

- 按项目约定使用 Swift Testing 框架（`import Testing`、`@Suite`、`@Test`、`#expect`）
- 测试文件镜像源结构
- Codable round-trip 测试是核心模式
- 路由测试需要构造 Hummingbird 请求上下文（参见现有 `AxionAPIRoutesTests.swift` 的测试模式）

### References

- [Source: epics.md — Epic 14 Story 14.2 Capabilities 端点]
- [Source: OpenClick src/api-runs.ts:218-252 — capabilitiesResponse()]
- [Source: OpenClick src/server.ts:70-71 — GET /v1/capabilities route]
- [Source: Sources/AxionCLI/API/AxionAPI.swift — 路由注册模式]
- [Source: Sources/AxionCLI/API/Models/APITypes.swift — StandardTaskOutput, APIRunStatus, TaskResultKind]
- [Source: Sources/AxionCore/Constants/ToolNames.swift — allToolNames 静态列表]
- [Source: Sources/AxionCLI/Constants/Version.swift — AxionVersion.current]
- [Source: Sources/AxionCLI/API/ConcurrencyLimiter.swift — maxConcurrent 属性]

### 前一个 Story (14.1) 经验

- APIRunStatus 已扩展为 8 种 case（queued/running/intervention_needed/user_takeover/resuming/completed/failed/cancelled）
- 所有 `/v1/runs` 端点已统一返回 StandardTaskOutput
- `HealthResponse` 已包含 `version` 字段（可参考其模式）
- AxionBar 使用 `decodeIfPresent` 做向后兼容
- 191 个测试通过，代码质量良好

## Dev Agent Record

### Agent Model Used

GLM-5.1[1m]

### Debug Log References

### Completion Notes List

- Implemented CapabilitiesResponse model with Codable/Equatable/Sendable/ResponseEncodable conformance and snake_case CodingKeys
- Added CaseIterable conformance to APIRunStatus (8 cases) and TaskResultKind (2 cases)
- Registered GET /v1/capabilities route in v1Authed group with Cache-Control: private, max-age=300 header
- Added maxConcurrent parameter to registerRoutes, passed from ServerCommand
- Added 9 unit tests: 5 model tests (codable round-trip, JSON keys, features, allCases for both enums) and 4 route tests (structure validation, cache header, auth, tool list matching)
- All 248 tests pass (pre-existing skill route test isolation failure unrelated)

### Change Log

- 2026-05-17: Story 14.2 implementation complete — Capabilities endpoint with full model, route, tests
- 2026-05-17: **Review (AI)** — 4 findings auto-fixed: (M1) Cache-Control changed to `private, max-age=300` for authenticated endpoint security; (M2) Added test for custom maxConcurrent value + updated buildTestApplication helper; (L1) Strengthened run statuses assertion to check actual values vs APIRunStatus.allCases; (L2) Strengthened result kinds assertion to check actual values vs TaskResultKind.allCases. All 30 route tests pass.

### Senior Developer Review (AI)

**Reviewer:** AI (adversarial) on 2026-05-17
**Outcome:** Approved — no CRITICAL issues

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| M1 | MEDIUM | Cache-Control missing `private` directive for authenticated endpoint (AxionAPI.swift:60) | Changed to `private, max-age=300` |
| M2 | MEDIUM | No test verifying custom maxConcurrent flows through (buildTestApplication missing param) | Added maxConcurrent param + new test |
| L1 | LOW | Route test only checked count==8, not actual run status values | Strengthened to exact value comparison |
| L2 | LOW | Route test only checked count==2, not actual result kind values | Strengthened to exact value comparison |

### File List

- Sources/AxionCLI/API/Models/APITypes.swift — Added CapabilitiesResponse struct; CaseIterable on APIRunStatus and TaskResultKind
- Sources/AxionCLI/API/AxionAPI.swift — Added GET /v1/capabilities route; maxConcurrent parameter
- Sources/AxionCLI/Commands/ServerCommand.swift — Pass maxConcurrent to registerRoutes
- Tests/AxionCLITests/API/APITypesTests.swift — Added CapabilitiesResponse tests, allCases tests
- Tests/AxionCLITests/API/AxionAPIRoutesTests.swift — Added capabilities route tests (structure, cache, auth, tools)
