# 手工验收清单 — Story 1.2: Helper MCP Server 基础

Date: 2026-05-08
Story: 1-2-helper-mcp-server-foundation
Commit: pending

---

## AC1: MCP initialize 响应

**目标:** AxionHelper 启动后，通过 stdin 发送 MCP initialize 请求，返回正确的 initialize 响应。

**前置条件:** `swift build` 编译成功

**步骤:**
1. 终端运行: `.build/debug/AxionHelper`
2. 在 stdin 输入 MCP initialize 请求（Ctrl+D 或管道）
3. 验证 stdout 返回 JSON-RPC initialize 响应

**快捷验证:**
```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' | .build/debug/AxionHelper
```

**预期结果:**
- stdout 输出包含 `"result"` 字段的 JSON-RPC 响应
- 响应包含 `serverInfo.name = "AxionHelper"` 和 `serverInfo.version = "0.1.0"`
- 响应包含 `capabilities.tools` 声明

**通过标准:** [ ] Initialize 响应包含正确的服务端能力声明

---

## AC2: tools/list 响应

**目标:** 发送 tools/list 请求，返回所有已注册工具列表。

**步骤:**
1. 先发送 initialize 请求（同 AC1）
2. 发送 `notifications/initialized` 通知
3. 发送 tools/list 请求

**快捷验证（自动测试）:**
```bash
swift test --filter HelperMCPServerTests/test_toolsList
```

**预期结果:**
- 返回 15 个工具定义
- 每个工具包含 name、description、inputSchema
- 工具名列表: launch_app, list_apps, list_windows, get_window_state, click, double_click, right_click, type_text, press_key, hotkey, scroll, drag, screenshot, get_accessibility_tree, open_url
- 所有工具名使用 snake_case 格式

**通过标准:** [ ] tools/list 返回完整的 15 个 stub 工具

---

## AC3: 未知工具调用错误

**目标:** 调用未注册的工具名时返回错误。

**快捷验证:**
```bash
swift test --filter HelperMCPServerTests/test_unknownTool
```

**预期结果:**
- 返回 `isError: true` 的 ToolResult
- message 说明工具不存在

**通过标准:** [ ] 未知工具调用返回 isError=true 的错误响应

---

## AC4: EOF 优雅退出

**目标:** stdin 收到 EOF 时 Helper 进程优雅退出。

**步骤:**
```bash
echo "" | .build/debug/AxionHelper
echo $?  # 检查退出码
```

**快捷验证:**
```bash
swift test --filter HelperProcessSmokeTests/test_helperProcess_gracefulExitOnEOF
```

**预期结果:**
- 进程正常退出（exit code 0）
- 无 crash report 或信号终止

**通过标准:** [ ] EOF 后进程优雅退出，无崩溃

---

## 补充验证

### 编译验证
```bash
swift build    # 预期: Build complete!
swift test     # 预期: 54 tests, 0 failures
```

### 工具名一致性
```bash
# 验证 ToolRegistrar 中的工具名与 ToolNames.swift 常量一致
grep 'static let name' Sources/AxionHelper/MCP/ToolRegistrar.swift
grep 'static let' Sources/AxionCore/Constants/ToolNames.swift
```

### stdout 无杂讯
- AxionHelper 的 stdout 只输出 MCP JSON-RPC 响应
- 无 print() 调用、无日志输出混入 stdout

---

## 审查备注

- Package.swift 中 AxionHelper 额外依赖 MCPTool（spec 中未在 1.1 提及，但在 1.2 spec 中明确要求）
- MCPServer.run(transport: .stdio) 实际不阻塞，使用 session.waitUntilCompleted() 作为 workaround
- ToolRegistrar.swift 是单文件 262 行，stub 阶段可接受，1.3-1.5 实现时需拆分
