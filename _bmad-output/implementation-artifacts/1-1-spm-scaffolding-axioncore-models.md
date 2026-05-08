# Story 1.1: SPM 项目脚手架与 AxionCore 共享模型

Status: done

## Story

As a 开发者,
I want 项目有完整的三目标 SPM 结构和强类型共享模型,
So that 后续所有 Story 可以在类型安全的基础上开发.

## Acceptance Criteria

1. **AC1: SPM 编译成功**
   - Given 一个新的空目录
   - When 运行 `swift build`
   - Then 项目编译成功，生成 AxionCLI 和 AxionHelper 两个可执行目标
   - And AxionCore 作为 library target 存在

2. **AC2: Plan 模型 Codable round-trip**
   - Given Plan 模型包含 steps 和 stopWhen
   - When 用 JSON 初始化并编码后解码
   - Then 数据完整 round-trip，Value 枚举的 placeholder case（如 `$pid`）正确保留

3. **AC3: RunState 枚举完整性**
   - Given RunState 枚举定义
   - When 检查所有 case
   - Then 包含 planning / executing / verifying / replanning / done / blocked / needsClarification / cancelled / failed 所有状态

4. **AC4: AxionConfig Codable camelCase 输出**
   - Given AxionConfig 使用 Codable 默认策略
   - When 编码为 JSON
   - Then 输出 camelCase 格式（maxSteps, maxBatches, maxReplanRetries 等）

5. **AC5: AxionError MCP ToolResult 格式**
   - Given AxionError 枚举
   - When 转换为 MCP ToolResult 错误格式
   - Then 输出包含 error / message / suggestion 字段的 JSON

6. **AC6: Protocol 文件位置**
   - Given 所有 Protocol 定义（PlannerProtocol, ExecutorProtocol, VerifierProtocol, MCPClientProtocol, OutputProtocol）
   - When 检查文件位置
   - Then 位于 AxionCore/Protocols/ 目录

## Tasks / Subtasks

- [x] Task 1: 创建 Package.swift 和目录结构 (AC: #1)
  - [x] 1.1 创建 `Package.swift`（swift-tools-version: 6.1，macOS .v14，三个 target，三个依赖）
  - [x] 1.2 创建 Sources/AxionCore/ 目录及子目录 Models/、Protocols/、Errors/、Constants/
  - [x] 1.3 创建 Sources/AxionCLI/ 目录及子目录（Commands/、Planner/、Executor/、Verifier/、Engine/、Config/、Helper/、Trace/、Output/）
  - [x] 1.4 创建 Sources/AxionHelper/ 目录及子目录（MCP/、Services/、Models/）
  - [x] 1.5 创建 Tests/ 目录及三个测试子目录
  - [x] 1.6 创建 Prompts/ 和 Distribution/homebrew/ 目录
  - [x] 1.7 创建 AxionCLI/main.swift 和 AxionHelper/main.swift 占位入口
  - [x] 1.8 创建 .gitignore（排除 .build/、.swiftpm/、Packages/ 等）
  - [x] 1.9 运行 `swift build` 验证编译成功

- [x] Task 2: 实现 AxionCore 共享数据模型 (AC: #2, #3, #4, #5)
  - [x] 2.1 创建 `Sources/AxionCore/Models/Plan.swift`（Plan 结构体，含 id/task/steps/stopWhen/maxRetries）
  - [x] 2.2 创建 `Sources/AxionCore/Models/Step.swift`（Step 结构体 + Value 枚举，支持 placeholder case）
  - [x] 2.3 创建 `Sources/AxionCore/Models/StopCondition.swift`（StopCondition + StopType 枚举）
  - [x] 2.4 创建 `Sources/AxionCore/Models/RunState.swift`（RunState 枚举，9 个 case）
  - [x] 2.5 创建 `Sources/AxionCore/Models/RunContext.swift`（RunContext 结构体）
  - [x] 2.6 创建 `Sources/AxionCore/Models/ExecutedStep.swift`（已执行步骤记录）
  - [x] 2.7 创建 `Sources/AxionCore/Models/AxionConfig.swift`（配置模型，camelCase Codable）
  - [x] 2.8 创建 `Sources/AxionCore/Errors/AxionError.swift`（统一错误类型 + MCP ToolResult 转换）

- [x] Task 3: 实现 AxionCore Protocol 定义 (AC: #6)
  - [x] 3.1 创建 `Sources/AxionCore/Protocols/PlannerProtocol.swift`
  - [x] 3.2 创建 `Sources/AxionCore/Protocols/ExecutorProtocol.swift`
  - [x] 3.3 创建 `Sources/AxionCore/Protocols/VerifierProtocol.swift`
  - [x] 3.4 创建 `Sources/AxionCore/Protocols/MCPClientProtocol.swift`
  - [x] 3.5 创建 `Sources/AxionCore/Protocols/OutputProtocol.swift`

- [x] Task 4: 实现 AxionCore 常量 (AC: #1)
  - [x] 4.1 创建 `Sources/AxionCore/Constants/ToolNames.swift`（MCP 工具名常量）
  - [x] 4.2 创建 `Sources/AxionCore/Constants/ConfigKeys.swift`（配置键常量）

- [x] Task 5: 编写 AxionCore 单元测试 (AC: #2, #3, #4, #5)
  - [x] 5.1 创建 `Tests/AxionCoreTests/PlanTests.swift`（Plan round-trip、Value placeholder 编解码）
  - [x] 5.2 创建 `Tests/AxionCoreTests/RunStateTests.swift`（所有 case 存在、Codable round-trip）
  - [x] 5.3 创建 `Tests/AxionCoreTests/AxionConfigTests.swift`（camelCase JSON 输出、默认值验证）
  - [x] 5.4 创建 `Tests/AxionCoreTests/AxionErrorTests.swift`（MCP ToolResult 错误格式转换）
  - [x] 5.5 运行 `swift test` 确认所有测试通过

## Dev Notes

### 关键架构约束

**这是整个项目的第一个 Story。** 所有后续 Story 都依赖本 Story 产出的 Package.swift 结构和 AxionCore 模型。必须严格遵循架构文档的定义。

### Package.swift 关键决策

1. **swift-tools-version: 5.9** — 架构文档指定 5.9+。本地 Swift 版本是 6.2.4，完全兼容。注意：OpenAgentSDK 使用 `swift-tools-version: 6.1`，但 Axion 作为消费者不需要匹配 SDK 的 tools-version，只需 Swift 编译器版本 >= SDK 要求即可。Swift 6.2.4 > 6.1，满足要求。

2. **OpenAgentSDK 依赖方式** — 使用 `.package(path: "../open-agent-sdk-swift")` 本地路径依赖。这意味着 Axion 和 SDK 必须在同一父目录下（`/Users/nick/CascadeProjects/axion` 和 `/Users/nick/CascadeProjects/open-agent-sdk-swift`）。

3. **mcp-swift-sdk 来源** — 架构文档写的是 `https://github.com/modelcontextprotocol/swift-sdk`，但 OpenAgentSDK 实际使用的是 `https://github.com/DePasqualeOrg/mcp-swift-sdk.git`（在 SDK 的 Package.resolved 中确认）。AxionHelper 不直接依赖 mcp-swift-sdk——它通过 OpenAgentSDK 间接获得。但在 AxionHelper 的依赖中，需要直接 import MCP（mcp-swift-sdk 提供的 product name 是 "MCP"）。因此 AxionHelper 的 mcp-swift-sdk 依赖 URL **必须与 SDK 使用的一致**：`https://github.com/DePasqualeOrg/mcp-swift-sdk.git, from: "0.1.0"`。

4. **ArgumentParser 版本** — `https://github.com/apple/swift-argument-parser, from: "1.5.0"`

5. **SPM target 配置**：
   - `.executableTarget(name: "AxionCLI", dependencies: ["AxionCore", .product(name: "OpenAgentSDK", package: "open-agent-sdk-swift"), .product(name: "ArgumentParser", package: "swift-argument-parser")])`
   - `.executableTarget(name: "AxionHelper", dependencies: ["AxionCore", .product(name: "MCP", package: "mcp-swift-sdk")])`
   - `.target(name: "AxionCore")` — 无外部依赖，纯 Swift

6. **platforms** — `.macOS(.v14)` 是最低要求。

### 数据模型精确定义

所有模型来自架构决策 D2（Plan 数据模型）和 D3（执行循环状态机）。以下是需要实现的精确结构：

**Plan.swift:**
```swift
struct Plan: Codable {
    let id: UUID
    let task: String
    let steps: [Step]
    let stopWhen: [StopCondition]
    let maxRetries: Int
}
```

**Step.swift:**
```swift
struct Step: Codable {
    let index: Int
    let tool: String
    let parameters: [String: Value]
    let purpose: String
    let expectedChange: String
}

enum Value: Codable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case placeholder(String)  // $pid, $window_id 等
}
```
Value 枚举的 Codable 实现需要特别注意：placeholder case 必须在 JSON round-trip 中正确保留。建议使用带 type discriminator 的编码策略（如 `{"type": "placeholder", "value": "$pid"}`）。

**RunState.swift:**
```swift
enum RunState: String, Codable {
    case planning
    case executing
    case verifying
    case replanning
    case done
    case blocked
    case needsClarification
    case cancelled
    case failed
}
```
共 9 个 case，必须全部包含。

**AxionConfig.swift:**
```swift
struct AxionConfig: Codable {
    var apiKey: String?           // 从 Keychain 读取，不在此文件存储
    var model: String             // 默认 "claude-sonnet-4-20250514"
    var maxSteps: Int             // 默认 20
    var maxBatches: Int           // 默认 6
    var maxReplanRetries: Int     // 默认 3
    var traceEnabled: Bool        // 默认 true
    var sharedSeatMode: Bool      // 默认 true
}
```
Codable 默认策略输出 camelCase JSON。可用 `CodingKeys` 确保字段名一致。

**AxionError.swift:**
统一错误枚举，包含到 MCP ToolResult 格式的转换方法。MCP 错误 JSON 格式：
```json
{"error": "error_code", "message": "人类可读描述", "suggestion": "修复建议"}
```

### Protocol 定义要点

所有 Protocol 定义为 AxionCore 的一部分，使用 async 函数签名（D5: Swift Structured Concurrency）。协议方法签名不需要在本 Story 中完全精确——后续 Story 会细化。本 Story 只需定义协议骨架，确保文件存在且位于正确位置。

### 命名规则（必须遵守）

| 类别 | 规则 | 示例 |
|------|------|------|
| 类型 | PascalCase | Plan, RunState, PlannerProtocol |
| 函数/方法 | camelCase，动词开头 | executeStep(), loadPrompt() |
| 属性/变量 | camelCase | maxSteps, currentPlan |
| 枚举 case | camelCase | .done, .needsClarification |
| 协议 | 名词 + Protocol 后缀 | PlannerProtocol, ExecutorProtocol |
| 文件名 | 与主类型同名 | Plan.swift, RunState.swift |
| 目录名 | PascalCase 复数 | Commands/, Services/, Models/ |

### import 顺序（所有文件必须遵守）

```swift
// 1. 系统框架
import Foundation
// 2. 第三方依赖
import OpenAgentSDK
// 3. 项目内部模块
import AxionCore
```

### 禁止事项（反模式）

- **AxionCore 中不得 import 任何外部依赖**（Core 是纯模型层，无外部依赖）
- **AxionCLI 不得 import AxionHelper**（两者仅通过 MCP 通信）
- **不得使用 print() 输出**（必须通过统一的 Output 协议）
- **不得硬编码 prompt 文本**

### 测试要求

- 测试命名格式：`test_方法名_场景_预期结果`
- 测试文件镜像源文件结构：`Tests/AxionCoreTests/` 对应 `Sources/AxionCore/`
- 不 Mock 纯数据结构——直接测试 Codable round-trip
- 运行命令：`swift test`

### Project Structure Notes

完整目录结构已在架构文档的「完整项目目录结构」部分定义到文件级别。本 Story 需要创建以下所有目录和文件：

**必须创建的文件（最小可编译集）：**
- `Package.swift`
- `.gitignore`
- `Sources/AxionCore/Models/Plan.swift`
- `Sources/AxionCore/Models/Step.swift`
- `Sources/AxionCore/Models/StopCondition.swift`
- `Sources/AxionCore/Models/RunState.swift`
- `Sources/AxionCore/Models/RunContext.swift`
- `Sources/AxionCore/Models/ExecutedStep.swift`
- `Sources/AxionCore/Models/AxionConfig.swift`
- `Sources/AxionCore/Errors/AxionError.swift`
- `Sources/AxionCore/Protocols/PlannerProtocol.swift`
- `Sources/AxionCore/Protocols/ExecutorProtocol.swift`
- `Sources/AxionCore/Protocols/VerifierProtocol.swift`
- `Sources/AxionCore/Protocols/MCPClientProtocol.swift`
- `Sources/AxionCore/Protocols/OutputProtocol.swift`
- `Sources/AxionCore/Constants/ToolNames.swift`
- `Sources/AxionCore/Constants/ConfigKeys.swift`
- `Sources/AxionCLI/main.swift`（占位入口，仅 `print("Axion CLI placeholder")` 或 ArgumentParser 骨架）
- `Sources/AxionHelper/main.swift`（占位入口，仅 `print("Axion Helper placeholder")`）
- 测试文件（PlanTests.swift, RunStateTests.swift, AxionConfigTests.swift, AxionErrorTests.swift）

**必须创建的空目录（用于后续 Story）：**
- `Sources/AxionCLI/Commands/`
- `Sources/AxionCLI/Planner/`
- `Sources/AxionCLI/Executor/`
- `Sources/AxionCLI/Verifier/`
- `Sources/AxionCLI/Engine/`
- `Sources/AxionCLI/Config/`
- `Sources/AxionCLI/Helper/`
- `Sources/AxionCLI/Trace/`
- `Sources/AxionCLI/Output/`
- `Sources/AxionHelper/MCP/`
- `Sources/AxionHelper/Services/`
- `Sources/AxionHelper/Models/`
- `Tests/AxionCLITests/`
- `Tests/AxionHelperTests/`
- `Prompts/`
- `Distribution/homebrew/`

注意：SPM 不需要空目录——只需在后续 Story 中按需创建文件即可。但 `.gitkeep` 文件可以用于保持目录结构可见。不建议使用 `.gitkeep`，因为 SPM 不关心空目录。

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#D2] Plan 数据模型定义
- [Source: _bmad-output/planning-artifacts/architecture.md#D3] 执行循环状态机设计
- [Source: _bmad-output/planning-artifacts/architecture.md#D4] 配置系统（AxionConfig 结构）
- [Source: _bmad-output/planning-artifacts/architecture.md#D5] 并发模型（async/await + Actor）
- [Source: _bmad-output/planning-artifacts/architecture.md#命名模式] 三套命名规则
- [Source: _bmad-output/planning-artifacts/architecture.md#结构模式] 文件归属和模块依赖规则
- [Source: _bmad-output/planning-artifacts/architecture.md#完整项目目录结构] 40+ 文件的完整目录树
- [Source: _bmad-output/planning-artifacts/architecture.md#Package.swift 关键决策] SPM 清单定义
- [Source: _bmad-output/planning-artifacts/architecture.md#格式模式] 错误返回格式和 Trace 格式
- [Source: _bmad-output/planning-artifacts/architecture.md#反模式] 必须避免的编码模式
- [Source: _bmad-output/planning-artifacts/epics.md#Story 1.1] 原始 Story 定义和 AC
- [Source: open-agent-sdk-swift/Package.swift] SDK 实际 tools-version 和依赖声明
- [Source: open-agent-sdk-swift/Package.resolved] SDK 实际使用的 mcp-swift-sdk 来源（DePasqualeOrg）

## Dev Agent Record

### Agent Model Used

GLM-5.1

### Debug Log References

- `swift build` 成功，Build complete! (33.85s)
- `swift test` 全部通过，34 tests, 0 failures
- 修复了预存在的 ATDD scaffold 文件 (SPMScaffoldTests.swift) 中的编译错误：移除 XCTSkip 调用、修正 AxionConfig 初始化、修正 Protocol 类型引用、修正 AxionError case 名称

### Completion Notes List

- Task 1: 创建了完整的 SPM 项目结构（Package.swift + 三个 target + 三个依赖 + 目录树 + .gitignore）。`swift build` 编译成功，AxionCLI 和 AxionHelper 可执行目标均生成。
- Task 2: 实现了 7 个共享数据模型 + 1 个错误类型。Value 枚举使用 type discriminator 编码策略确保 placeholder case 正确 round-trip。AxionError 包含 12 个 case 和 MCP ToolResult JSON 转换方法。AxionConfig 提供 static default 常量。
- Task 3: 实现了 5 个 Protocol 骨架（async 函数签名），全部位于 AxionCore/Protocols/ 目录。
- Task 4: 实现了 ToolNames 和 ConfigKeys 两个常量枚举。
- Task 5: 编写了 4 个测试文件共 24 个测试 + 修复了 ATDD scaffold 中的 10 个测试。全部 34 个测试通过。

### File List

- Package.swift (new)
- .gitignore (new)
- Sources/AxionCLI/main.swift (new)
- Sources/AxionHelper/main.swift (new)
- Sources/AxionCore/Models/Plan.swift (new)
- Sources/AxionCore/Models/Step.swift (new)
- Sources/AxionCore/Models/StopCondition.swift (new)
- Sources/AxionCore/Models/RunState.swift (new)
- Sources/AxionCore/Models/RunContext.swift (new)
- Sources/AxionCore/Models/ExecutedStep.swift (new)
- Sources/AxionCore/Models/AxionConfig.swift (new)
- Sources/AxionCore/Errors/AxionError.swift (new)
- Sources/AxionCore/Protocols/PlannerProtocol.swift (new)
- Sources/AxionCore/Protocols/ExecutorProtocol.swift (new)
- Sources/AxionCore/Protocols/VerifierProtocol.swift (new)
- Sources/AxionCore/Protocols/MCPClientProtocol.swift (new)
- Sources/AxionCore/Protocols/OutputProtocol.swift (new)
- Sources/AxionCore/Constants/ToolNames.swift (new)
- Sources/AxionCore/Constants/ConfigKeys.swift (new)
- Tests/AxionCoreTests/PlanTests.swift (new)
- Tests/AxionCoreTests/RunStateTests.swift (new)
- Tests/AxionCoreTests/AxionConfigTests.swift (new)
- Tests/AxionCoreTests/AxionErrorTests.swift (new)
- Tests/AxionCoreTests/SPMScaffoldTests.swift (modified)
- Tests/AxionCLITests/.gitkeep (new)
- Tests/AxionHelperTests/.gitkeep (new)
