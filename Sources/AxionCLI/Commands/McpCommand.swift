import ArgumentParser
import Foundation

import AxionCore

/// `axion mcp` — Start an MCP stdio server exposing Axion's desktop automation tools.
struct McpCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "启动 MCP stdio 服务器，暴露 Axion 工具供外部 Agent 调用",
        discussion: """
        将 Axion 配置为 MCP server 供外部 Agent（如 Claude Code、Cursor）调用。

        Claude Code 配置示例（添加到 .claude/settings.json）：
          {
            "mcpServers": {
              "axion": {
                "command": "axion",
                "args": ["mcp"]
              }
            }
          }

        可用工具：
        - run_task: 异步提交桌面自动化任务
        - query_task_status: 查询任务执行状态
        - list_apps, launch_app, click, type_text 等: 直接桌面操作

        使用 --verbose 启用详细日志（输出到 stderr，不影响 MCP 协议通信）。
        """
    )

    @Flag(name: .long, help: "详细输出")
    var verbose: Bool = false

    func run() async throws {
        let config = try await ConfigManager.loadConfig()
        let runner = MCPServerRunner(config: config, verbose: verbose)
        try await runner.run()
    }
}
