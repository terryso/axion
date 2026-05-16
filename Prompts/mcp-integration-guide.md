# Axion MCP Server 集成指南

Axion 可以作为 MCP (Model Context Protocol) stdio 服务器运行，将桌面自动化能力暴露给外部 AI Agent。

## 启动 MCP Server

```bash
axion mcp              # 标准模式
axion mcp --verbose    # 详细日志模式（日志输出到 stderr）
```

## Claude Code 配置

在 `.claude/settings.json`（项目级）或 `~/.claude/settings.json`（全局）中添加：

```json
{
  "mcpServers": {
    "axion": {
      "command": "axion",
      "args": ["mcp"]
    }
  }
}
```

启用详细日志：

```json
{
  "mcpServers": {
    "axion": {
      "command": "axion",
      "args": ["mcp", "--verbose"]
    }
  }
}
```

Claude Code 启动时会自动执行 `axion mcp`，通过 stdin/stdout 建立 MCP JSON-RPC 通信。

## Cursor 配置

在 Cursor 设置中添加 MCP server：

```json
{
  "mcpServers": {
    "axion": {
      "command": "axion",
      "args": ["mcp"]
    }
  }
}
```

配置路径：`~/.cursor/mcp.json`

## 其他 MCP 兼容客户端

任何支持 MCP stdio 协议的客户端都可以使用相同配置模式：

```json
{
  "mcpServers": {
    "axion": {
      "command": "axion",
      "args": ["mcp"]
    }
  }
}
```

确保 `axion` 在系统 PATH 中可用（`axion doctor` 可验证）。

## 可用工具

Axion MCP server 暴露以下工具：

### 任务管理

| 工具 | 说明 |
|------|------|
| `run_task` | 异步提交桌面自动化任务，返回 run_id 用于跟踪 |
| `query_task_status` | 查询任务执行状态（running/done/failed） |

### 桌面操作

| 工具 | 说明 |
|------|------|
| `list_apps` | 列出运行中的应用 |
| `launch_app` | 启动应用 |
| `click` | 点击坐标 |
| `type_text` | 输入文本 |
| `press_key` | 按键操作 |
| `scroll` | 滚动操作 |
| `screenshot` | 截图 |
| `get_ax_tree` | 获取无障碍树 |
| `get_window_state` | 获取窗口状态 |
| `open_url` | 打开 URL |

## 前提条件

1. **API Key**: 运行 `axion setup` 配置 Anthropic API Key
2. **AxionHelper**: 确保 Helper 应用已安装（`axion doctor` 检查）
3. **PATH**: `axion` 命令在 PATH 中可用

## 故障排查

- **工具未被发现**: 检查 `axion doctor` 输出确认环境正常
- **Helper 连接失败**: 确认 AxionHelper 在 `libexec/axion/` 目录中
- **API Key 错误**: 运行 `axion setup` 重新配置
- **启用 verbose 日志**: 使用 `--verbose` 参数，日志输出到 stderr 不影响 MCP 通信
