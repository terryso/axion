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

    // MARK: - renderTurnSummary

    @Test("renderTurnSummary: TrueColor TTY 包含 dim 分隔线和统计信息")
    func renderTurnSummary_trueColor() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "3.2s",
            toolCount: 2,
            inputTokens: "1.2k",
            outputTokens: "856"
        )
        #expect(result.contains("3.2s"))
        #expect(result.contains("2 tools"))
        #expect(result.contains("↑1.2k"))
        #expect(result.contains("↓856"))
        #expect(result.contains("──"))
        #expect(result.contains("\u{1B}[38;2;"))  // TrueColor dim gray
    }

    @Test("renderTurnSummary: 非 TTY 使用 [turn: ...] 纯文本格式")
    func renderTurnSummary_nonTTY() {
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "350ms",
            toolCount: 0,
            inputTokens: "500",
            outputTokens: "120"
        )
        #expect(result.contains("[turn:"))
        #expect(result.contains("350ms"))
        #expect(result.contains("0 tools"))
        #expect(result.contains("↑500"))
        #expect(result.contains("↓120"))
        #expect(!result.contains("\u{1B}"))
    }

    @Test("renderTurnSummary: 1 tool 使用单数形式")
    func renderTurnSummary_singularTool() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "1.0s",
            toolCount: 1,
            inputTokens: "2k",
            outputTokens: "300"
        )
        #expect(result.contains("1 tool"))
        #expect(!result.contains("1 tools"))
    }

    // MARK: - renderTurnSummary with Context Bar

    @Test("renderTurnSummary: 含上下文进度条 TrueColor TTY")
    func renderTurnSummary_withContextBar_trueColor() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "5.0s",
            toolCount: 3,
            inputTokens: "5k",
            outputTokens: "2k",
            contextPct: 45
        )
        // 基本统计
        #expect(result.contains("5.0s"))
        #expect(result.contains("3 tools"))
        #expect(result.contains("↑5k"))
        #expect(result.contains("↓2k"))
        // 上下文百分比
        #expect(result.contains("45%"))
        // 进度条字符
        #expect(result.contains("█"))
        #expect(result.contains("░"))
        // 分隔线
        #expect(result.contains("──"))
    }

    @Test("renderTurnSummary: 含上下文进度条非 TTY 纯文本")
    func renderTurnSummary_withContextBar_nonTTY() {
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "1.0s",
            toolCount: 1,
            inputTokens: "500",
            outputTokens: "200",
            contextPct: 30
        )
        #expect(result.contains("[turn:"))
        #expect(result.contains("ctx 30%"))
        #expect(!result.contains("█"))  // 非 TTY 不显示进度条
        #expect(!result.contains("──"))  // 非 TTY 不显示 box-drawing 分隔线
    }

    @Test("renderTurnSummary: 含预估成本 TrueColor TTY")
    func renderTurnSummary_withCost_trueColor() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "3.2s",
            toolCount: 2,
            inputTokens: "1.2k",
            outputTokens: "856",
            estimatedCost: "$0.0123"
        )
        #expect(result.contains("$0.0123"))
        #expect(result.contains("──"))
    }

    @Test("renderTurnSummary: 含预估成本非 TTY")
    func renderTurnSummary_withCost_nonTTY() {
        let theme = ChatTheme(profile: .unknown, isTTY: false)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "500ms",
            toolCount: 0,
            inputTokens: "100",
            outputTokens: "50",
            estimatedCost: "$0.0005"
        )
        #expect(result.contains("[turn:"))
        #expect(result.contains("$0.0005"))
        #expect(!result.contains("\u{1B}"))
    }

    @Test("renderTurnSummary: 同时含上下文和成本")
    func renderTurnSummary_withContextAndCost() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "10.0s",
            toolCount: 5,
            inputTokens: "10k",
            outputTokens: "4k",
            contextPct: 72,
            estimatedCost: "$0.0567"
        )
        #expect(result.contains("10.0s"))
        #expect(result.contains("5 tools"))
        #expect(result.contains("72%"))
        #expect(result.contains("$0.0567"))
        #expect(result.contains("█"))
        #expect(result.contains("░"))
    }

    @Test("renderTurnSummary: 无上下文和成本时不额外显示")
    func renderTurnSummary_withoutContextAndCost() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "1.0s",
            toolCount: 0,
            inputTokens: "200",
            outputTokens: "100"
        )
        // 不包含上下文段和成本
        #expect(!result.contains("ctx"))
        #expect(!result.contains("%"))  // 无上下文百分比
        #expect(!result.contains("$"))  // 无成本
        // 但包含基本统计
        #expect(result.contains("1.0s"))
        #expect(result.contains("0 tools"))
    }

    @Test("renderTurnSummary: 高上下文使用率 >80% 使用红色")
    func renderTurnSummary_highContextUsage() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "2.0s",
            toolCount: 1,
            inputTokens: "1k",
            outputTokens: "500",
            contextPct: 85
        )
        #expect(result.contains("85%"))
        // 红色 TrueColor 码 (38;2;244;67;54)
        #expect(result.contains("244;67;54"))
    }

    @Test("renderTurnSummary: 中等上下文使用率 50-80% 使用黄色")
    func renderTurnSummary_mediumContextUsage() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "2.0s",
            toolCount: 1,
            inputTokens: "1k",
            outputTokens: "500",
            contextPct: 65
        )
        #expect(result.contains("65%"))
        // 黄色 TrueColor 码 (38;2;255;193;7)
        #expect(result.contains("255;193;7"))
    }

    @Test("renderTurnSummary: 低上下文使用率 <50% 使用绿色")
    func renderTurnSummary_lowContextUsage() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "2.0s",
            toolCount: 1,
            inputTokens: "1k",
            outputTokens: "500",
            contextPct: 20
        )
        #expect(result.contains("20%"))
        // 绿色 TrueColor 码 (38;2;76;175;80)
        #expect(result.contains("76;175;80"))
    }

    @Test("renderTurnSummary: 上下文进度条 ANSI256 降级")
    func renderTurnSummary_contextBar_ansi256() {
        let theme = ChatTheme(profile: .ansi256, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "1.0s",
            toolCount: 1,
            inputTokens: "500",
            outputTokens: "200",
            contextPct: 45
        )
        #expect(result.contains("45%"))
        #expect(result.contains("\u{1B}[38;5;"))  // ANSI256 颜色码
        #expect(result.contains("█"))
    }

    @Test("renderTurnSummary: 上下文进度条 ANSI16 降级")
    func renderTurnSummary_contextBar_ansi16() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "1.0s",
            toolCount: 1,
            inputTokens: "500",
            outputTokens: "200",
            contextPct: 45
        )
        #expect(result.contains("45%"))
        #expect(result.contains("\u{1B}[32m"))  // ANSI16 绿色
        #expect(result.contains("█"))
    }

    @Test("renderTurnSummary: contextPct=0 显示空进度条")
    func renderTurnSummary_contextBar_zeroPct() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "500ms",
            toolCount: 0,
            inputTokens: "100",
            outputTokens: "50",
            contextPct: 0
        )
        #expect(result.contains("0%"))
        // 全空进度条
        #expect(!result.contains("█"))
        #expect(result.contains("░"))
    }

    @Test("renderTurnSummary: contextPct=100 满进度条")
    func renderTurnSummary_contextBar_fullPct() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "5.0s",
            toolCount: 3,
            inputTokens: "10k",
            outputTokens: "5k",
            contextPct: 100
        )
        #expect(result.contains("100%"))
        // 全满进度条，无空格
        #expect(!result.contains("░"))
        #expect(result.contains("█"))
    }

    @Test("renderTurnSummary: nil contextPct 和 nil estimatedCost 不崩溃")
    func renderTurnSummary_nilOptionals() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        let result = renderer.renderTurnSummary(
            duration: "1.0s",
            toolCount: 1,
            inputTokens: "500",
            outputTokens: "200",
            contextPct: nil,
            estimatedCost: nil
        )
        #expect(result.contains("1.0s"))
        #expect(result.contains("1 tool"))
        #expect(!result.contains("ctx"))
        #expect(!result.contains("$"))
    }

    @Test("renderTurnSummary: 成本为零时不显示成本")
    func renderTurnSummary_zeroCostNotShown() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let renderer = TranscriptRenderer(theme: theme)
        // empty string is treated as "show nothing"
        let result = renderer.renderTurnSummary(
            duration: "1.0s",
            toolCount: 0,
            inputTokens: "100",
            outputTokens: "50",
            estimatedCost: nil
        )
        #expect(!result.contains("$"))
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
