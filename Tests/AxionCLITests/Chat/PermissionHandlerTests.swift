import Testing
import OpenAgentSDK

@testable import AxionCLI

@Suite("PermissionHandler")
struct PermissionHandlerTests {

    // MARK: - Mock Tool

    /// Minimal mock tool for testing permission logic.
    private struct MockTool: ToolProtocol {
        let toolName: String
        let readOnly: Bool

        var name: String { toolName }
        var description: String { "Mock tool" }
        var inputSchema: ToolInputSchema { [:] }
        var isReadOnly: Bool { readOnly }

        func call(input: Any, context: ToolContext) async -> ToolResult {
            ToolResult(toolUseId: "test", content: "ok", isError: false)
        }
    }

    // MARK: - Helper

    /// Creates a ToolContext for testing.
    private func makeContext() -> ToolContext {
        ToolContext(cwd: "/tmp")
    }

    // MARK: - AC4: Read-only tools auto-allow in all modes

    @Test("只读工具在 default 模式自动通过")
    func readOnlyToolAutoAllows() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: false,  // non-TTY — would normally deny
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Read", readOnly: true)
        let result = await canUseTool(tool, [:], makeContext())
        #expect(result?.behavior == .allow)
    }

    @Test("只读工具在 acceptEdits 模式自动通过")
    func readOnlyToolAcceptEdits() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .acceptEdits,
            isTTY: false,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Grep", readOnly: true)
        let result = await canUseTool(tool, [:], makeContext())
        #expect(result?.behavior == .allow)
    }

    @Test("只读工具在 bypassPermissions 模式自动通过")
    func readOnlyToolBypass() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .bypassPermissions,
            isTTY: false,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Glob", readOnly: true)
        let result = await canUseTool(tool, [:], makeContext())
        #expect(result?.behavior == .allow)
    }

    // MARK: - AC3: bypassPermissions auto-allows all tools

    @Test("bypassPermissions 模式所有工具自动通过")
    func bypassAllowsAll() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .bypassPermissions,
            isTTY: false,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "rm -rf /"], makeContext())
        #expect(result?.behavior == .allow)
    }

    // MARK: - AC2: acceptEdits auto-allows Write/Edit

    @Test("acceptEdits 模式 Write 工具自动通过")
    func acceptEditsWriteAutoAllows() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .acceptEdits,
            isTTY: true,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Write", readOnly: false)
        let result = await canUseTool(tool, ["file_path": "/tmp/test.txt"], makeContext())
        #expect(result?.behavior == .allow)
    }

    @Test("acceptEdits 模式 Edit 工具自动通过")
    func acceptEditsEditAutoAllows() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .acceptEdits,
            isTTY: true,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Edit", readOnly: false)
        let result = await canUseTool(tool, ["file_path": "src/main.swift"], makeContext())
        #expect(result?.behavior == .allow)
    }

    @Test("acceptEdits 模式 Bash 仍需确认（用户输入 y）")
    func acceptEditsBashNeedsConfirmation() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .acceptEdits,
            isTTY: true,
            readUserInput: { "y" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls"], makeContext())
        #expect(result?.behavior == .allow)
    }

    @Test("acceptEdits 模式 Bash 用户拒绝")
    func acceptEditsBashDenied() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .acceptEdits,
            isTTY: true,
            readUserInput: { "n" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "rm -rf /"], makeContext())
        #expect(result?.behavior == .deny)
    }

    // MARK: - AC1: default mode permission prompt

    @Test("default 模式用户输入 y 允许执行")
    func defaultModeUserAllows() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            readUserInput: { "y" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls -la"], makeContext())
        #expect(result?.behavior == .allow)
    }

    @Test("default 模式用户输入 n 拒绝执行")
    func defaultModeUserDenies() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            readUserInput: { "n" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "rm -rf /"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("用户拒绝") == true)
    }

    @Test("default 模式用户输入 yes 允许执行")
    func defaultModeUserSaysYes() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            readUserInput: { "yes" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "echo test"], makeContext())
        #expect(result?.behavior == .allow)
    }

    @Test("default 模式用户输入空行拒绝执行")
    func defaultModeEmptyInput() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            readUserInput: { "" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "echo test"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("用户拒绝") == true)
    }

    // MARK: - Non-TTY safety default

    @Test("非 TTY 环境拒绝非只读工具")
    func nonTTYDeniesNonReadOnly() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: false,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("非终端环境") == true)
    }

    @Test("default 模式 non-TTY 环境拒绝非只读工具")
    func defaultNonTTYDeniesNonReadOnly() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: false,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("非终端环境") == true)
    }

    @Test("acceptEdits 模式 non-TTY + Write 自动通过")
    func acceptEditsNonTTYWriteAutoAllows() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .acceptEdits,
            isTTY: false,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Write", readOnly: false)
        let result = await canUseTool(tool, ["file_path": "/tmp/test.txt"], makeContext())
        #expect(result?.behavior == .allow)
    }

    @Test("acceptEdits 模式 non-TTY + Bash 拒绝")
    func acceptEditsNonTTYBashDenied() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .acceptEdits,
            isTTY: false,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "rm -rf /"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("非终端环境") == true)
    }

    @Test("TTY 环境 readLine 返回 nil 时拒绝（EOF）")
    func ttyReadLineNilDenies() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("无法读取") == true)
    }

    // MARK: - Description extraction

    @Test("Bash 工具提取 command 参数")
    func bashDescriptionExtraction() {
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let desc = PermissionHandler.extractDescription(
            tool: tool, input: ["command": "rm -rf /tmp/test"]
        )
        #expect(desc == "rm -rf /tmp/test")
    }

    @Test("Write 工具提取 file_path 参数")
    func writeDescriptionExtraction() {
        let tool = MockTool(toolName: "Write", readOnly: false)
        let desc = PermissionHandler.extractDescription(
            tool: tool, input: ["file_path": "Sources/main.swift"]
        )
        #expect(desc == "写入 Sources/main.swift")
    }

    @Test("Edit 工具提取 file_path 参数")
    func editDescriptionExtraction() {
        let tool = MockTool(toolName: "Edit", readOnly: false)
        let desc = PermissionHandler.extractDescription(
            tool: tool, input: ["file_path": "Tests/MyTests.swift"]
        )
        #expect(desc == "编辑 Tests/MyTests.swift")
    }

    @Test("未知工具使用工具名作为描述")
    func unknownToolDescription() {
        let tool = MockTool(toolName: "SomeTool", readOnly: false)
        let desc = PermissionHandler.extractDescription(
            tool: tool, input: ["foo": "bar"]
        )
        #expect(desc == "SomeTool")
    }

    @Test("Bash 工具无 command 参数时回退到工具名")
    func bashMissingCommand() {
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let desc = PermissionHandler.extractDescription(
            tool: tool, input: [:]
        )
        #expect(desc == "Bash")
    }

    @Test("input 不是字典时回退到工具名")
    func inputNotDictionary() {
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let desc = PermissionHandler.extractDescription(
            tool: tool, input: "not a dict"
        )
        #expect(desc == "Bash")
    }

    // MARK: - Mode resolution

    @Test("默认 flag 组合 → default 模式")
    func resolveDefaultMode() {
        let mode = PermissionHandler.resolveMode(
            acceptEdits: false,
            dangerouslySkipPermissions: false
        )
        #expect(mode == .default)
    }

    @Test("--accept-edits → acceptEdits 模式")
    func resolveAcceptEditsMode() {
        let mode = PermissionHandler.resolveMode(
            acceptEdits: true,
            dangerouslySkipPermissions: false
        )
        #expect(mode == .acceptEdits)
    }

    @Test("--dangerously-skip-permissions → bypassPermissions 模式")
    func resolveBypassMode() {
        let mode = PermissionHandler.resolveMode(
            acceptEdits: false,
            dangerouslySkipPermissions: true
        )
        #expect(mode == .bypassPermissions)
    }

    @Test("两个 flag 同时设置时 bypassPermissions 优先")
    func bothFlagsBypassWins() {
        let mode = PermissionHandler.resolveMode(
            acceptEdits: true,
            dangerouslySkipPermissions: true
        )
        #expect(mode == .bypassPermissions)
    }

    // MARK: - Mode display name

    @Test("modeDisplayName 返回正确字符串")
    func modeDisplayNames() {
        #expect(PermissionHandler.modeDisplayName(.default) == "default")
        #expect(PermissionHandler.modeDisplayName(.acceptEdits) == "acceptEdits")
        #expect(PermissionHandler.modeDisplayName(.bypassPermissions) == "bypassPermissions")
        #expect(PermissionHandler.modeDisplayName(.plan) == "plan")
        #expect(PermissionHandler.modeDisplayName(.dontAsk) == "dontAsk")
        #expect(PermissionHandler.modeDisplayName(.auto) == "auto")
    }
}
