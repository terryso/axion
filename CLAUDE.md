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
