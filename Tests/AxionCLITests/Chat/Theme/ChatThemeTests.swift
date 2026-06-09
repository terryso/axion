import Foundation
import Testing

@testable import AxionCLI

// [P0] 基础设施验证 — ChatTheme 格式化方法
// TDD RED PHASE: 测试引用尚未实现的 ChatTheme 类型

@Suite("ChatTheme")
struct ChatThemeTests {

    // MARK: - formatRoleDot (AC1/AC2/AC3)

    @Test("trueColor: 用户角色圆点包含蓝色 ANSI 码和圆点字符")
    func formatRoleDot_trueColor_user() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let dot = theme.formatRoleDot(role: .user)
        #expect(dot.contains("\u{1B}[38;2;"))
        #expect(dot.contains("●"))
        #expect(dot.contains("\u{1B}[0m"))
    }

    @Test("trueColor: AI 角色圆点包含绿色 ANSI 码")
    func formatRoleDot_trueColor_assistant() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let dot = theme.formatRoleDot(role: .assistant)
        #expect(dot.contains("\u{1B}[38;2;"))
        #expect(dot.contains("●"))
    }

    @Test("trueColor: 工具角色圆点包含黄色 ANSI 码")
    func formatRoleDot_trueColor_tool() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let dot = theme.formatRoleDot(role: .tool)
        #expect(dot.contains("\u{1B}[38;2;"))
        #expect(dot.contains("●"))
    }

    @Test("trueColor: 警告角色圆点包含红色 ANSI 码")
    func formatRoleDot_trueColor_warning() {
        let theme = ChatTheme(profile: .trueColor, isTTY: true)
        let dot = theme.formatRoleDot(role: .warning)
        #expect(dot.contains("\u{1B}[38;2;"))
        #expect(dot.contains("●"))
    }

    @Test("ansi16: 用户角色圆点使用标准蓝色码 34")
    func formatRoleDot_ansi16_user() {
        let theme = ChatTheme(profile: .ansi16, isTTY: true)
        let dot = theme.formatRoleDot(role: .user)
        #expect(dot.contains("\u{1B}[34m"))
        #expect(dot.contains("●"))
        #expect(dot.contains("\u{1B}[0m"))
    }

    // MARK: - formatPlainText 纯文本回退 (AC4)

    @Test("unknown profile: formatPlainText 用户返回 [user]")
    func formatPlainText_user() {
        let theme = ChatTheme(profile: .unknown, isTTY: true)
        let text = theme.formatPlainText(role: .user)
        #expect(text == "[user]")
    }

    @Test("unknown profile: formatPlainText AI 返回 [ai]")
    func formatPlainText_assistant() {
        let theme = ChatTheme(profile: .unknown, isTTY: true)
        let text = theme.formatPlainText(role: .assistant)
        #expect(text == "[ai]")
    }

    @Test("unknown profile: formatPlainText 工具返回 [tool]")
    func formatPlainText_tool() {
        let theme = ChatTheme(profile: .unknown, isTTY: true)
        let text = theme.formatPlainText(role: .tool)
        #expect(text == "[tool]")
    }

    @Test("unknown profile: formatPlainText 警告返回 [warn]")
    func formatPlainText_warning() {
        let theme = ChatTheme(profile: .unknown, isTTY: true)
        let text = theme.formatPlainText(role: .warning)
        #expect(text == "[warn]")
    }

    // MARK: - 非 TTY 回退 (AC4)

    @Test("非 TTY: formatRoleDot 使用纯文本前缀而非 ANSI 码")
    func formatRoleDot_nonTTY_user() {
        let theme = ChatTheme(profile: .trueColor, isTTY: false)
        let dot = theme.formatRoleDot(role: .user)
        #expect(!dot.contains("\u{1B}"))
        #expect(dot.contains("[user]"))
    }

    @Test("非 TTY: formatRoleDot AI 使用纯文本前缀")
    func formatRoleDot_nonTTY_assistant() {
        let theme = ChatTheme(profile: .trueColor, isTTY: false)
        let dot = theme.formatRoleDot(role: .assistant)
        #expect(!dot.contains("\u{1B}"))
        #expect(dot.contains("[ai]"))
    }
}
