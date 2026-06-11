# Axion 项目规则

## 测试框架

- **全部使用 Swift Testing 框架**（`import Testing`、`@Suite`、`@Test`、`#expect`）。
- **不再使用 XCTest**。`grep -rl "import XCTest" Tests/` 应返回空。
- 迁移参考：`Tests/AxionBarTests/Models/ConnectionStateTests.swift`

## 测试执行规则

- **开发完成后只运行单元测试，不运行集成测试。**
- 单元测试目录：`Tests/**/Tools/`、`Tests/**/Models/`、`Tests/**/MCP/`、`Tests/**/Services/`
- 集成测试目录：`Tests/**/Integration/`、`Tests/**/AxionE2ETests/`（需要真实 macOS 应用和 AX 权限）
- 运行命令：`swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"`
- GitHub CI 也只跑单元测试，不跑集成测试（CI 环境无 AX 权限）。

## 单元测试必须 Mock

- **单元测试禁止调用真实外部依赖**：AgentBuilder.build()、RunOrchestrator.execute()、MCP 连接、Helper 进程、osascript 桌面通知等。
- **用 Protocol 抽象 + Mock 实现**：对具体依赖（RunOrchestrator、AgentBuilder、通知等）抽取 Protocol，测试中注入 Mock 实现。参考：`RunExecuting`、`AgentBuilding` Protocol + `MockRunExecutor`、`MockAgentBuilder`。
- **禁止在测试中弹系统通知**：NotificationHandler 等涉及系统副作用的组件，必须通过注入闭包（如 `notify` 参数）替换为 no-op mock。
- **构造不可直接实例化的类型**：如果被测类型依赖 SDK 内部类型（如 AgentBuildResult），在测试中通过 `@testable import` 直接构造所需字段，而非调用真实 build 方法。
