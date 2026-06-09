import Testing

@testable import AxionCLI

// MARK: - AC5/AC7/AC9: ApprovalRenderer 测试

@Suite("ApprovalRenderer")
struct ApprovalRendererTests {

    // MARK: - TTY 主题

    /// 创建 TTY + ansi16 主题用于测试
    private func makeTTYTheme() -> ChatTheme {
        ChatTheme(profile: .ansi16, isTTY: true)
    }

    /// 创建非 TTY 主题
    private func makeNonTTYTheme() -> ChatTheme {
        ChatTheme(profile: .unknown, isTTY: false)
    }

    // MARK: - AC5: 审批提示渲染

    @Test("renderPrompt 包含工具名和操作描述")
    func renderPromptContainsToolAndDescription() {
        let theme = makeTTYTheme()
        let options = ApprovalOption.allOptions(
            toolName: "Bash",
            input: ["command": "swift test"]
        )
        let result = ApprovalRenderer.renderPrompt(
            toolName: "Bash",
            description: "swift test",
            options: options,
            theme: theme
        )
        #expect(result.contains("Bash"))
        #expect(result.contains("swift test"))
    }

    @Test("renderPrompt 包含红色圆点")
    func renderPromptContainsWarningDot() {
        let theme = makeTTYTheme()
        let options = ApprovalOption.allOptions(toolName: "Bash", input: ["command": "ls"])
        let result = ApprovalRenderer.renderPrompt(
            toolName: "Bash",
            description: "ls",
            options: options,
            theme: theme
        )
        // TTY + ansi16: warning 角色使用 \u{1B}[31m (red)
        #expect(result.contains("\u{1B}[31m"))
        #expect(result.contains("●"))
    }

    @Test("renderPrompt 非 TTY 不含 ANSI 颜色码")
    func renderPromptNonTTYNoColor() {
        let theme = makeNonTTYTheme()
        let options = ApprovalOption.allOptions(toolName: "Bash", input: ["command": "ls"])
        let result = ApprovalRenderer.renderPrompt(
            toolName: "Bash",
            description: "ls",
            options: options,
            theme: theme
        )
        #expect(result.contains("[warn]"))
        #expect(!result.contains("\u{1B}["))
    }

    // MARK: - 选项列表渲染

    @Test("renderOptionsList 包含编号/快捷键/标签")
    func renderOptionsList() {
        let options = ApprovalOption.allOptions(
            toolName: "Bash",
            input: ["command": "swift test"]
        )
        let result = ApprovalRenderer.renderOptionsList(options)
        #expect(result.contains("[y]"))
        #expect(result.contains("仅本次"))
        #expect(result.contains("[a]"))
        #expect(result.contains("本会话"))
        #expect(result.contains("[p]"))
        #expect(result.contains("[d]"))
        #expect(result.contains("拒绝"))
        #expect(result.contains("[Esc]"))
        #expect(result.contains("取消"))
    }

    @Test("renderOptionsList Write 工具无 prefix 选项")
    func renderOptionsListWrite() {
        let options = ApprovalOption.allOptions(toolName: "Write", input: [:])
        let result = ApprovalRenderer.renderOptionsList(options)
        #expect(!result.contains("[p]"))
        #expect(result.contains("[y]"))
        #expect(result.contains("[a]"))
    }

    // MARK: - AC7: Diff 摘要

    @Test("diff 摘要: Edit 工具显示行数变更")
    func editDiffSummary() {
        let input: [String: Any] = [
            "file_path": "src/main.swift",
            "old_string": "line1\nline2\nline3",
            "new_string": "line1\nnew_line\nline3\nline4"
        ]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Edit", input: input)
        #expect(result != nil)
        #expect(result!.contains("src/main.swift"))
        // old: 3 lines, new: 4 lines → +1 added
        #expect(result!.contains("+1"))
    }

    @Test("diff 摘要: Edit 工具删除行")
    func editDiffSummaryRemoval() {
        let input: [String: Any] = [
            "file_path": "test.swift",
            "old_string": "a\nb\nc\nd",
            "new_string": "a\nc"
        ]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Edit", input: input)
        #expect(result != nil)
        // old: 4 lines, new: 2 lines → -2
        #expect(result!.contains("-2"))
    }

    @Test("diff 摘要: Edit 工具替换同行数")
    func editDiffSummarySameLines() {
        let input: [String: Any] = [
            "file_path": "app.swift",
            "old_string": "a\nb",
            "new_string": "x\ny"
        ]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Edit", input: input)
        #expect(result != nil)
        #expect(result!.contains("替换 2 行"))
    }

    @Test("diff 摘要: Write 工具显示文件行数")
    func writeDiffSummary() {
        let input: [String: Any] = [
            "file_path": "new_file.swift",
            "content": "line1\nline2\nline3"
        ]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Write", input: input)
        #expect(result != nil)
        #expect(result!.contains("new_file.swift"))
        #expect(result!.contains("3 行"))
    }

    @Test("diff 摘要: Write 工具缺 content 返回 nil")
    func writeDiffSummaryNoContent() {
        let input: [String: Any] = ["file_path": "test.swift"]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Write", input: input)
        #expect(result == nil)
    }

    @Test("diff 摘要: Edit 工具缺 old_string/new_string 返回 nil")
    func editDiffSummaryMissingFields() {
        let input: [String: Any] = ["file_path": "test.swift"]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Edit", input: input)
        #expect(result == nil)
    }

    @Test("diff 摘要: Bash 工具无摘要")
    func bashNoDiffSummary() {
        let input: [String: Any] = ["command": "ls"]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Bash", input: input)
        #expect(result == nil)
    }

    @Test("diff 摘要: 缺 file_path 使用 '文件' 作为默认")
    func diffSummaryDefaultFilePath() {
        let input: [String: Any] = [
            "old_string": "a",
            "new_string": "b\nc"
        ]
        let result = ApprovalRenderer.renderDiffSummary(toolName: "Edit", input: input)
        #expect(result != nil)
        #expect(result!.contains("文件"))
    }
}
