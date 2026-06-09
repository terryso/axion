import Foundation
import Testing

@testable import AxionCLI

@Suite("KeyHintsFormatter")
struct KeyHintsFormatterTests {

    // MARK: - KeyHint

    @Test("KeyHint.plain 渲染为 [key] description 格式")
    func keyHint_plain() {
        let hint = KeyHintsFormatter.KeyHint(key: "Ctrl+C", description: "中断")
        #expect(hint.plain == "[Ctrl+C] 中断")
    }

    @Test("KeyHint.colored unknown profile 降级为纯文本")
    func keyHint_colored_unknownProfile() {
        let hint = KeyHintsFormatter.KeyHint(key: "Esc", description: "清空")
        let result = hint.colored(profile: .unknown)
        #expect(result == "[Esc] 清空")
        #expect(!result.contains("\u{1B}"))  // 无 ANSI escape
    }

    @Test("KeyHint.colored trueColor profile 包含 ANSI 颜色码")
    func keyHint_colored_trueColor() {
        let hint = KeyHintsFormatter.KeyHint(key: "Enter", description: "发送")
        let result = hint.colored(profile: .trueColor)
        #expect(result.contains("[Enter]"))
        #expect(result.contains("发送"))
        #expect(result.contains("\u{1B}[0m"))  // reset
        #expect(result.contains("\u{1B}[38;2;"))  // 24-bit color
    }

    @Test("KeyHint.colored ansi16 profile 包含基础颜色码")
    func keyHint_colored_ansi16() {
        let hint = KeyHintsFormatter.KeyHint(key: "Ctrl+R", description: "搜索")
        let result = hint.colored(profile: .ansi16)
        #expect(result.contains("[Ctrl+R]"))
        #expect(result.contains("\u{1B}[36m"))  // cyan for key
    }

    // MARK: - renderInline

    @Test("renderInline 非 TTY 输出纯文本用 · 分隔")
    func renderInline_nonTTY() {
        let result = KeyHintsFormatter.renderInline(
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(!result.contains("\u{1B}"))
        #expect(result.contains("[Enter]"))
        #expect(result.contains("发送"))
        #expect(result.contains("·"))
        #expect(result.contains("[/help]"))
        #expect(result.contains("命令列表"))
    }

    @Test("renderInline TTY 输出包含 ANSI 颜色码")
    func renderInline_tty() {
        let result = KeyHintsFormatter.renderInline(
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(result.contains("\u{1B}[0m"))  // reset
        #expect(result.contains("\u{1B}[38;2;"))  // 24-bit color
        #expect(result.contains("·"))
    }

    @Test("renderInline 默认使用 coreHints（5 个快捷键）")
    func renderInline_defaultHints() {
        let result = KeyHintsFormatter.renderInline(isTTY: false, colorProfile: .unknown)
        let parts = result.components(separatedBy: " · ")
        #expect(parts.count == 5)
    }

    @Test("renderInline 自定义提示列表")
    func renderInline_customHints() {
        let customHints = [
            KeyHintsFormatter.KeyHint(key: "A", description: "Alpha"),
            KeyHintsFormatter.KeyHint(key: "B", description: "Beta"),
        ]
        let result = KeyHintsFormatter.renderInline(
            isTTY: false,
            colorProfile: .unknown,
            hints: customHints
        )
        #expect(result == "[A] Alpha · [B] Beta")
    }

    @Test("renderInline 空提示列表返回空字符串")
    func renderInline_emptyHints() {
        let result = KeyHintsFormatter.renderInline(
            isTTY: false,
            colorProfile: .unknown,
            hints: []
        )
        #expect(result.isEmpty)
    }

    // MARK: - renderFull

    @Test("renderFull 非 TTY 输出分组格式，无 ANSI 码")
    func renderFull_nonTTY() {
        let result = KeyHintsFormatter.renderFull(
            isTTY: false,
            colorProfile: .unknown
        )
        #expect(!result.contains("\u{1B}"))
        #expect(result.contains("输入"))
        #expect(result.contains("导航"))
        #expect(result.contains("编辑"))
        #expect(result.contains("队列"))
        #expect(result.contains("斜杠命令"))
        // Each group should have separator line
        #expect(result.contains("------"))
    }

    @Test("renderFull TTY 输出包含 ANSI 颜色和下划线")
    func renderFull_tty() {
        let result = KeyHintsFormatter.renderFull(
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(result.contains("\u{1B}[0m"))
        #expect(result.contains("\u{1B}[4m"))  // underline for labels
        // Unicode dash for TTY
        #expect(result.contains("──"))
    }

    @Test("renderFull 包含所有快捷键分组")
    func renderFull_containsAllGroups() {
        let result = KeyHintsFormatter.renderFull(isTTY: false, colorProfile: .unknown)
        #expect(result.contains("[Enter] 发送消息"))
        #expect(result.contains("[↑/↓] 历史导航"))
        #expect(result.contains("[Ctrl+G] 外部编辑器"))
        #expect(result.contains("[Ctrl+Q] 入队消息"))
        #expect(result.contains("[/cost] Token 用量"))
    }

    @Test("renderFull 自定义分组")
    func renderFull_customGroups() {
        let customGroups = [
            KeyHintsFormatter.HintGroup(label: "测试", hints: [
                KeyHintsFormatter.KeyHint(key: "X", description: "Test"),
            ])
        ]
        let result = KeyHintsFormatter.renderFull(
            isTTY: false,
            colorProfile: .unknown,
            groups: customGroups
        )
        #expect(result.contains("测试"))
        #expect(result.contains("[X] Test"))
        #expect(!result.contains("输入"))  // 不含默认分组
    }

    @Test("renderFull 空分组返回仅空行")
    func renderFull_emptyGroups() {
        let result = KeyHintsFormatter.renderFull(
            isTTY: false,
            colorProfile: .unknown,
            groups: []
        )
        #expect(result.isEmpty)
    }

    // MARK: - coreHints and allGroups

    @Test("coreHints 包含关键快捷键")
    func coreHints_containsEssentialKeys() {
        let keys = KeyHintsFormatter.coreHints.map(\.key)
        #expect(keys.contains("Enter"))
        #expect(keys.contains("Esc"))
        #expect(keys.contains("Ctrl+C"))
        #expect(keys.contains("/help"))
    }

    @Test("allGroups 包含 5 个分组")
    func allGroups_count() {
        #expect(KeyHintsFormatter.allGroups.count == 5)
    }

    @Test("allGroups 每个分组至少有 1 个提示")
    func allGroups_nonEmpty() {
        for group in KeyHintsFormatter.allGroups {
            #expect(!group.hints.isEmpty)
        }
    }

    // MARK: - HintGroup

    @Test("HintGroup.Equatable 正确比较")
    func hintGroup_equality() {
        let group1 = KeyHintsFormatter.HintGroup(label: "A", hints: [
            KeyHintsFormatter.KeyHint(key: "X", description: "Test")
        ])
        let group2 = KeyHintsFormatter.HintGroup(label: "A", hints: [
            KeyHintsFormatter.KeyHint(key: "X", description: "Test")
        ])
        let group3 = KeyHintsFormatter.HintGroup(label: "B", hints: [])
        #expect(group1 == group2)
        #expect(group1 != group3)
    }

    // MARK: - KeyHint.Equatable

    @Test("KeyHint.Equatable 正确比较")
    func keyHint_equality() {
        let h1 = KeyHintsFormatter.KeyHint(key: "A", description: "Alpha")
        let h2 = KeyHintsFormatter.KeyHint(key: "A", description: "Alpha")
        let h3 = KeyHintsFormatter.KeyHint(key: "B", description: "Alpha")
        let h4 = KeyHintsFormatter.KeyHint(key: "A", description: "Beta")
        #expect(h1 == h2)
        #expect(h1 != h3)
        #expect(h1 != h4)
    }
}
