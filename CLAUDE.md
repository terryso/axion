# Axion 项目规则

## 测试执行规则

- **开发完成后只运行单元测试，不运行集成测试。**
- 单元测试目录：`Tests/**/Tools/`、`Tests/**/Models/`、`Tests/**/MCP/`、`Tests/**/Services/`
- 集成测试目录：`Tests/**/Integration/`（需要真实 macOS 应用和 AX 权限）
- 运行命令：`swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"`
- GitHub CI 也只跑单元测试，不跑集成测试（CI 环境无 AX 权限）。
