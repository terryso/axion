import Testing

@testable import AxionCLI

// MARK: - AC1: ApprovalDecision 枚举测试

@Suite("ApprovalDecision")
struct ApprovalDecisionTests {

    // MARK: - 快捷键测试

    @Test("once 快捷键为 y")
    func onceShortcut() {
        #expect(ApprovalDecision.once.shortcut == "y")
    }

    @Test("session 快捷键为 a")
    func sessionShortcut() {
        #expect(ApprovalDecision.session.shortcut == "a")
    }

    @Test("prefix 快捷键为 p")
    func prefixShortcut() {
        #expect(ApprovalDecision.prefix("git commit*").shortcut == "p")
    }

    @Test("decline 快捷键为 d")
    func declineShortcut() {
        #expect(ApprovalDecision.decline.shortcut == "d")
    }

    // MARK: - 标签测试

    @Test("once 标签为 '仅本次'")
    func onceLabel() {
        #expect(ApprovalDecision.once.label == "仅本次")
    }

    @Test("session 标签为 '本会话'")
    func sessionLabel() {
        #expect(ApprovalDecision.session.label == "本会话")
    }

    @Test("prefix 标签包含前缀预览")
    func prefixLabel() {
        let decision = ApprovalDecision.prefix("git commit*")
        #expect(decision.label == "前缀: git commit*")
    }

    @Test("decline 标签为 '拒绝'")
    func declineLabel() {
        #expect(ApprovalDecision.decline.label == "拒绝")
    }

    // MARK: - 快捷键显示文本

    @Test("所有决策快捷键显示为单字符")
    func shortcutDisplay() {
        #expect(ApprovalDecision.once.shortcutDisplay == "y")
        #expect(ApprovalDecision.session.shortcutDisplay == "a")
        #expect(ApprovalDecision.prefix("x").shortcutDisplay == "p")
        #expect(ApprovalDecision.decline.shortcutDisplay == "d")
    }

    // MARK: - Equatable

    @Test("两个 prefix 决策相等当且仅当前缀文本相同")
    func prefixEquality() {
        #expect(ApprovalDecision.prefix("git commit*") == ApprovalDecision.prefix("git commit*"))
        #expect(ApprovalDecision.prefix("git commit*") != ApprovalDecision.prefix("git push*"))
    }
}

// MARK: - AC2: ApprovalOption 动态选项测试

@Suite("ApprovalOption")
struct ApprovalOptionTests {

    // MARK: - Bash 工具选项

    @Test("Bash 工具包含 4 个选项（once, session, prefix, decline）")
    func bashAllOptions() {
        let options = ApprovalOption.allOptions(
            toolName: "Bash",
            input: ["command": "swift test"]
        )
        #expect(options.count == 4)

        #expect(options[0].decision == .once)
        #expect(options[1].decision == .session)
        // options[2] 是 prefix，携带前缀预览
        if case .prefix(let preview) = options[2].decision {
            #expect(preview == "swift test*")
        } else {
            Issue.record("Expected prefix decision")
        }
        #expect(options[3].decision == .decline)
    }

    @Test("Bash 工具 prefix 选项显示前缀预览")
    func bashPrefixPreview() {
        let options = ApprovalOption.allOptions(
            toolName: "Bash",
            input: ["command": "git commit -m \"fix: bug\""]
        )
        let prefixOption = options.first { if case .prefix = $0.decision { true } else { false } }
        #expect(prefixOption != nil)
        #expect(prefixOption!.label.contains("git commit*"))
    }

    @Test("Bash 工具 prefix 选项快捷键为 p")
    func bashPrefixShortcut() {
        let options = ApprovalOption.allOptions(
            toolName: "Bash",
            input: ["command": "swift build"]
        )
        let prefixOption = options.first { if case .prefix = $0.decision { true } else { false } }
        #expect(prefixOption?.shortcut == "p")
    }

    // MARK: - Write/Edit 工具选项

    @Test("Write 工具不包含 prefix 选项")
    func writeNoPrefix() {
        let options = ApprovalOption.allOptions(
            toolName: "Write",
            input: ["file_path": "/tmp/test.txt"]
        )
        #expect(options.count == 3)
        let hasPrefix = options.contains { if case .prefix = $0.decision { true } else { false } }
        #expect(!hasPrefix)
    }

    @Test("Edit 工具不包含 prefix 选项")
    func editNoPrefix() {
        let options = ApprovalOption.allOptions(
            toolName: "Edit",
            input: ["file_path": "src/main.swift"]
        )
        #expect(options.count == 3)
        let hasPrefix = options.contains { if case .prefix = $0.decision { true } else { false } }
        #expect(!hasPrefix)
    }

    @Test("Write 工具选项顺序: once, session, decline")
    func writeOptionOrder() {
        let options = ApprovalOption.allOptions(
            toolName: "Write",
            input: [:]
        )
        #expect(options[0].decision == .once)
        #expect(options[1].decision == .session)
        #expect(options[2].decision == .decline)
    }

    @Test("Bash 单 token 命令不包含 prefix 选项")
    func bashSingleTokenNoPrefix() {
        let options = ApprovalOption.allOptions(
            toolName: "Bash",
            input: ["command": "make"]
        )
        #expect(options.count == 3)
        let hasPrefix = options.contains { if case .prefix = $0.decision { true } else { false } }
        #expect(!hasPrefix)
    }

    @Test("Bash 空命令不包含 prefix 选项")
    func bashEmptyCommandNoPrefix() {
        let options = ApprovalOption.allOptions(
            toolName: "Bash",
            input: ["command": ""]
        )
        #expect(options.count == 3)
        let hasPrefix = options.contains { if case .prefix = $0.decision { true } else { false } }
        #expect(!hasPrefix)
    }

    @Test("Bash nil input 不包含 prefix 选项")
    func bashNilInputNoPrefix() {
        let options = ApprovalOption.allOptions(
            toolName: "Bash",
            input: nil
        )
        #expect(options.count == 3)
    }

    // MARK: - 未知工具

    @Test("未知工具不包含 prefix 选项")
    func unknownToolNoPrefix() {
        let options = ApprovalOption.allOptions(
            toolName: "SomeTool",
            input: [:]
        )
        #expect(options.count == 3)
    }

    // MARK: - Tokenize

    @Test("tokenize 正确拆分简单命令")
    func tokenizeSimple() {
        let tokens = ApprovalOption.tokenize("git commit -m fix")
        #expect(tokens == ["git", "commit", "-m", "fix"])
    }

    @Test("tokenize 正确处理引号内空格")
    func tokenizeQuoted() {
        let tokens = ApprovalOption.tokenize("git commit -m \"fix: bug\"")
        #expect(tokens == ["git", "commit", "-m", "fix: bug"])
    }

    @Test("tokenize 单引号")
    func tokenizeSingleQuote() {
        let tokens = ApprovalOption.tokenize("echo 'hello world'")
        #expect(tokens == ["echo", "hello world"])
    }

    @Test("tokenize 多余空格")
    func tokenizeExtraSpaces() {
        let tokens = ApprovalOption.tokenize("  git   commit  ")
        #expect(tokens == ["git", "commit"])
    }

    @Test("tokenize 处理转义引号")
    func tokenizeEscapedQuotes() {
        let tokens = ApprovalOption.tokenize("echo \"hello \\\"world\\\"\"")
        #expect(tokens == ["echo", "hello \"world\""])
    }

    @Test("tokenize 处理反斜杠转义空格")
    func tokenizeEscapedSpace() {
        let tokens = ApprovalOption.tokenize("echo hello\\ world")
        #expect(tokens == ["echo", "hello world"])
    }

    // MARK: - Prefix Preview

    @Test("prefixPreview 多 token 命令取前 2 个")
    func prefixPreviewMultiToken() {
        let preview = ApprovalOption.prefixPreview(for: "git commit -m \"fix\"")
        #expect(preview == "git commit*")
    }

    @Test("prefixPreview 单 token 命令加星号")
    func prefixPreviewSingleToken() {
        let preview = ApprovalOption.prefixPreview(for: "make")
        #expect(preview == "make*")
    }

    @Test("prefixPreview 两 token 命令刚好取全部")
    func prefixPreviewTwoTokens() {
        let preview = ApprovalOption.prefixPreview(for: "swift build")
        #expect(preview == "swift build*")
    }

    @Test("prefixPreview 空命令返回空字符串")
    func prefixPreviewEmpty() {
        let preview = ApprovalOption.prefixPreview(for: "")
        #expect(preview == "")
    }

    @Test("prefixPreview 纯空格命令返回空字符串")
    func prefixPreviewWhitespace() {
        let preview = ApprovalOption.prefixPreview(for: "   ")
        #expect(preview == "")
    }
}
