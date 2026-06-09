import Foundation
import Testing

@testable import AxionCLI

// [P1] 行为验证 — TranscriptRenderer 角色消息块渲染
// TDD RED PHASE: 测试引用尚未实现的 TranscriptRenderer / TranscriptRole 类型

@Suite("TranscriptRenderer")
struct TranscriptRendererTests {

    // MARK: - renderUserMessage (AC1)

    @Test("renderUserMessage: TrueColor TTY 包含蓝色圆点和消息文本")
    func renderUserMessage_trueColor() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderUserMessage(text: "请帮我写一个函数")
        #expect(result.contains("●"))
        #expect(result.contains("请帮我写一个函数"))
        #expect(result.contains("\u{1B}[38;2;"))  // TrueColor 蓝色
    }

    @Test("renderUserMessage: 非 TTY 使用纯文本 [user] 前缀")
    func renderUserMessage_nonTTY() {
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderUserMessage(text: "hello")
        #expect(result.contains("[user]"))
        #expect(result.contains("hello"))
        #expect(!result.contains("\u{1B}"))
    }

    @Test("renderUserMessage: ansi16 包含标准蓝色码 34")
    func renderUserMessage_ansi16() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderUserMessage(text: "test")
        #expect(result.contains("\u{1B}[34m"))
        #expect(result.contains("●"))
    }

    // MARK: - renderAssistantBlockStart (AC2)

    @Test("renderAssistantBlockStart: TrueColor TTY 包含绿色圆点")
    func renderAssistantBlockStart_trueColor() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderAssistantBlockStart()
        #expect(result.contains("●"))
        #expect(result.contains("\u{1B}[38;2;"))  // TrueColor 绿色
    }

    @Test("renderAssistantBlockStart: 非 TTY 使用 [ai] 前缀")
    func renderAssistantBlockStart_nonTTY() {
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderAssistantBlockStart()
        #expect(result.contains("[ai]"))
        #expect(!result.contains("\u{1B}"))
    }

    // MARK: - renderWarning (AC3)

    @Test("renderWarning: TrueColor TTY 包含红色圆点")
    func renderWarning_trueColor() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderWarning(message: "达到最大步数限制")
        #expect(result.contains("●"))
        #expect(result.contains("达到最大步数限制"))
    }

    @Test("renderWarning: 非 TTY 使用 [warn] 前缀")
    func renderWarning_nonTTY() {
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderWarning(message: "timeout")
        #expect(result.contains("[warn]"))
        #expect(result.contains("timeout"))
        #expect(!result.contains("\u{1B}"))
    }

    @Test("renderWarning: ansi16 包含标准红色码 31")
    func renderWarning_ansi16() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderWarning(message: "error")
        #expect(result.contains("\u{1B}[31m"))
    }

    // MARK: - 窄终端兼容 (AC6)

    @Test("renderUserMessage: 短消息不崩溃（< 40 列终端）")
    func renderUserMessage_narrowTerminal() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderUserMessage(text: "ok")
        #expect(!result.isEmpty)
        #expect(result.contains("ok"))
    }

    // MARK: - tmux 兼容 (AC5)

    @Test("tmux 环境下 ansi256 渲染不包含 OSC 转义序列")
    func tmux_noOSCEscape() {
        let theme = ChatTheme(profile: .ansi256, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderUserMessage(text: "test")
        // 不应包含 OSC 序列（\033] 或 \x1b]）
        #expect(!result.contains("\u{1B}]"))
    }

    // MARK: - 渲染性能 (AC8)

    @Test("formatRoleDot 渲染性能 < 1ms")
    func formatRoleDot_performance() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let start = ContinuousClock.now
        for _ in 0..<1000 {
            _ = theme.formatRoleDot(role: .user)
        }
        let elapsed = ContinuousClock.now - start
        let msPerCall = Int(elapsed.components.seconds) * 1000
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        // 1000 次调用应 < 1000ms，即每次 < 1ms
        #expect(msPerCall < 1000)
    }
}
