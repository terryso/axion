import Testing
import OpenAgentSDK

@testable import AxionCLI

// MARK: - AC1–AC9: PermissionHandler v2 审批测试

@Suite("PermissionHandler V2")
struct PermissionHandlerV2Tests {

    // MARK: - Mock Tool

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

    private func makeContext() -> ToolContext {
        ToolContext(cwd: "/tmp")
    }

    // MARK: - AC3: Session 允许 — 首次审批后自动放行

    @Test("session 允许: 首次 a → 第二次自动放行")
    func sessionAllowAutoPass() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { "a" }
        )

        let tool = MockTool(toolName: "Bash", readOnly: false)
        let input: [String: Any] = ["command": "swift test"]

        // 第一次: 用户选择 session 允许
        let result1 = await canUseTool(tool, input, makeContext())
        #expect(result1?.behavior == .allow)

        // 第二次: 相同命令自动放行
        let result2 = await canUseTool(tool, input, makeContext())
        #expect(result2?.behavior == .allow)
    }

    // MARK: - AC4: Prefix 允许 — 前缀匹配自动放行

    @Test("prefix 允许: 首次 p → 同前缀命令自动放行")
    func prefixAllowAutoPass() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { "p" }
        )

        let tool = MockTool(toolName: "Bash", readOnly: false)

        // 第一次: git commit -m "fix"
        let input1: [String: Any] = ["command": "git commit -m \"fix: bug\""]
        let result1 = await canUseTool(tool, input1, makeContext())
        #expect(result1?.behavior == .allow)

        // 第二次: git commit -m "docs" → 同前缀 "git commit" 自动放行
        let input2: [String: Any] = ["command": "git commit -m \"docs: update\""]
        let result2 = await canUseTool(tool, input2, makeContext())
        #expect(result2?.behavior == .allow)

        // 第三次: git push → 不同前缀，需要审批
        // 但 readUserInput 固定返回 "d"（拒绝）
        let canUseTool2 = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { "d" }
        )
        let input3: [String: Any] = ["command": "git push origin main"]
        let result3 = await canUseTool2(tool, input3, makeContext())
        #expect(result3?.behavior == .deny)
    }

    // MARK: - AC6: 快捷键映射

    @Test("快捷键 y → once → 允许")
    func shortcutOnce() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { "y" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls"], makeContext())
        #expect(result?.behavior == .allow)
        // once 不注册到 allow list
        #expect(!allowList.isAllowed(command: "ls"))
    }

    @Test("快捷键 a → session 允许")
    func shortcutSession() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { "a" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "swift build"], makeContext())
        #expect(result?.behavior == .allow)
        #expect(allowList.isAllowed(command: "swift build"))
    }

    @Test("快捷键 p → prefix 允许")
    func shortcutPrefix() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { "p" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(
            tool,
            ["command": "git commit -m \"fix\""],
            makeContext()
        )
        #expect(result?.behavior == .allow)
        // prefix 允许后同前缀命令匹配
        #expect(allowList.isAllowed(command: "git commit -m \"docs\""))
    }

    @Test("快捷键 d → 拒绝")
    func shortcutDecline() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { "d" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "rm -rf /"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("拒绝") == true)
    }

    @Test("空输入 → cancel")
    func shortcutCancelEmpty() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { "" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("取消") == true)
    }

    // MARK: - AC8: 非 TTY 安全降级

    @Test("非 TTY 仍拒绝")
    func nonTTYDenies() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: false,
            sessionAllowList: allowList,
            readUserInput: { "y" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("非终端环境") == true)
    }

    @Test("v2 nil readUserInput (EOF) → 拒绝")
    func v2NilReadUserInput() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls"], makeContext())
        #expect(result?.behavior == .deny)
        #expect(result?.message?.contains("无法读取") == true)
    }

    // MARK: - 向后兼容: nil sessionAllowList

    @Test("nil sessionAllowList 使用 v1 [y/n] 行为")
    func nilAllowListV1Behavior() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: nil,
            readUserInput: { "y" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "ls"], makeContext())
        #expect(result?.behavior == .allow)
    }

    @Test("nil sessionAllowList + n → 拒绝")
    func nilAllowListDeny() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: nil,
            readUserInput: { "n" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "rm -rf /"], makeContext())
        #expect(result?.behavior == .deny)
    }

    // MARK: - 只读工具不受 v2 影响

    @Test("v2 只读工具仍自动通过")
    func v2ReadOnlyAutoAllows() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Read", readOnly: true)
        let result = await canUseTool(tool, [:], makeContext())
        #expect(result?.behavior == .allow)
    }

    // MARK: - bypassPermissions + sessionAllowList

    @Test("v2 bypassPermissions 忽略 allowList")
    func v2BypassOverrides() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .bypassPermissions,
            isTTY: false,
            sessionAllowList: allowList,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "rm -rf /"], makeContext())
        #expect(result?.behavior == .allow)
    }

    // MARK: - acceptEdits + sessionAllowList

    @Test("v2 acceptEdits + Write 自动通过")
    func v2AcceptEditsWriteAutoAllows() async {
        let allowList = SessionAllowListRef()
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .acceptEdits,
            isTTY: true,
            sessionAllowList: allowList,
            readUserInput: { nil }
        )
        let tool = MockTool(toolName: "Write", readOnly: false)
        let result = await canUseTool(
            tool,
            ["file_path": "/tmp/test.txt"],
            makeContext()
        )
        #expect(result?.behavior == .allow)
    }

    // MARK: - Command Key Extraction

    @Test("extractCommandKey: Bash → command")
    func commandKeyBash() {
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let key = PermissionHandler.extractCommandKey(
            tool: tool,
            input: ["command": "swift test"]
        )
        #expect(key == "swift test")
    }

    @Test("extractCommandKey: Write → Write:{file_path}")
    func commandKeyWrite() {
        let tool = MockTool(toolName: "Write", readOnly: false)
        let key = PermissionHandler.extractCommandKey(
            tool: tool,
            input: ["file_path": "src/main.swift"]
        )
        #expect(key == "Write:src/main.swift")
    }

    @Test("extractCommandKey: Edit → Edit:{file_path}")
    func commandKeyEdit() {
        let tool = MockTool(toolName: "Edit", readOnly: false)
        let key = PermissionHandler.extractCommandKey(
            tool: tool,
            input: ["file_path": "Tests/XTests.swift"]
        )
        #expect(key == "Edit:Tests/XTests.swift")
    }

    @Test("extractCommandKey: 未知工具返回 nil")
    func commandKeyUnknown() {
        let tool = MockTool(toolName: "SomeTool", readOnly: false)
        let key = PermissionHandler.extractCommandKey(tool: tool, input: [:])
        #expect(key == nil)
    }

    // MARK: - mapInputToDecision

    @Test("mapInputToDecision: y → once")
    func mapY() {
        let options = ApprovalOption.allOptions(toolName: "Bash", input: ["command": "ls"])
        let decision = PermissionHandler.mapInputToDecision("y", options: options)
        #expect(decision == .once)
    }

    @Test("mapInputToDecision: a → session")
    func mapA() {
        let options = ApprovalOption.allOptions(toolName: "Bash", input: ["command": "ls"])
        let decision = PermissionHandler.mapInputToDecision("a", options: options)
        #expect(decision == .session)
    }

    @Test("mapInputToDecision: p → prefix")
    func mapP() {
        let options = ApprovalOption.allOptions(toolName: "Bash", input: ["command": "git commit -m fix"])
        let decision = PermissionHandler.mapInputToDecision("p", options: options)
        if case .prefix = decision {
            // expected
        } else {
            Issue.record("Expected prefix decision, got \(decision)")
        }
    }

    @Test("mapInputToDecision: d → decline")
    func mapD() {
        let options = ApprovalOption.allOptions(toolName: "Bash", input: ["command": "ls"])
        let decision = PermissionHandler.mapInputToDecision("d", options: options)
        #expect(decision == .decline)
    }

    @Test("mapInputToDecision: 空 → cancel")
    func mapEmpty() {
        let options = ApprovalOption.allOptions(toolName: "Bash", input: ["command": "ls"])
        let decision = PermissionHandler.mapInputToDecision("", options: options)
        #expect(decision == .cancel)
    }

    @Test("mapInputToDecision: 未知字符 → decline")
    func mapUnknown() {
        let options = ApprovalOption.allOptions(toolName: "Bash", input: ["command": "ls"])
        let decision = PermissionHandler.mapInputToDecision("x", options: options)
        #expect(decision == .decline)
    }

    @Test("mapInputToDecision: 大写 Y → once")
    func mapUpperCase() {
        let options = ApprovalOption.allOptions(toolName: "Bash", input: ["command": "ls"])
        let decision = PermissionHandler.mapInputToDecision("Y", options: options)
        #expect(decision == .once)
    }

    // MARK: - 原有测试兼容性

    @Test("v1 原有测试: default 模式 yes 允许执行")
    func v1YesAllowed() async {
        let canUseTool = PermissionHandler.createCanUseTool(
            mode: .default,
            isTTY: true,
            readUserInput: { "yes" }
        )
        let tool = MockTool(toolName: "Bash", readOnly: false)
        let result = await canUseTool(tool, ["command": "echo test"], makeContext())
        #expect(result?.behavior == .allow)
    }
}
