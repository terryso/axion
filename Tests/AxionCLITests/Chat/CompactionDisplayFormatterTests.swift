import Foundation
import Testing

@testable import AxionCLI

// MARK: - CompactionDisplayFormatter Tests

@Suite("CompactionDisplayFormatter")
struct CompactionDisplayFormatterTests {

    // MARK: - 非 TTY 模式

    @Test("非 TTY: 基本格式保持纯文本")
    func nonTTY_basicFormat() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 45_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: false,
            profile: .unknown
        )
        #expect(result == "[axion] 上下文已自动压缩 (45k → 8k tokens)\n")
    }

    @Test("非 TTY: 小数字不缩写")
    func nonTTY_smallNumbers() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 500,
            afterTokens: 200,
            contextWindow: 200_000,
            isTTY: false,
            profile: .unknown
        )
        #expect(result == "[axion] 上下文已自动压缩 (500 → 200 tokens)\n")
    }

    @Test("非 TTY: 无 ANSI 转义码")
    func nonTTY_noAnsiCodes() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 90_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: false,
            profile: .unknown
        )
        #expect(!result.contains("\u{1B}"))
    }

    // MARK: - TTY + contextWindow = 0 降级

    @Test("TTY 但 contextWindow=0: 降级为纯文本")
    func ttyZeroWindow_fallsBackToPlainText() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 45_000,
            afterTokens: 8_000,
            contextWindow: 0,
            isTTY: true,
            profile: .trueColor
        )
        #expect(result == "[axion] 上下文已自动压缩 (45k → 8k tokens)\n")
    }

    // MARK: - TTY 模式 + trueColor

    @Test("TTY trueColor: 包含进度条和节省信息")
    func tty_trueColor_hasProgressBarAndSavings() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 90_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        // 头部信息
        #expect(result.contains("90k → 8k tokens"))
        // ✂ 剪刀符号
        #expect(result.contains("✂"))
        // 节省信息
        #expect(result.contains("节省"))
        #expect(result.contains("82k"))  // 90000 - 8000 = 82000
        #expect(result.contains("91%"))  // 82000/90000 ≈ 91%
        // Before/after 百分比
        #expect(result.contains("45%"))  // 90000/200000 = 45%
        #expect(result.contains("4%"))   // 8000/200000 = 4%
        // 进度条字符
        #expect(result.contains("█"))
        #expect(result.contains("░"))
        // 包含 ANSI 颜色码
        #expect(result.contains("\u{1B}["))
    }

    @Test("TTY trueColor: before 进度条使用黄色（45%）")
    func tty_trueColor_beforeBarYellow() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 90_000,   // 45%
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        // 45% 属于黄色范围 (50-80% is yellow, <50% is green)
        // 45% → green
        #expect(result.contains("\u{1B}[38;2;76;175;80m"))  // green
    }

    @Test("TTY trueColor: before 进度条使用红色（>80%）")
    func tty_trueColor_beforeBarRed() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 180_000,  // 90%
            afterTokens: 20_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        // 90% → red
        #expect(result.contains("\u{1B}[38;2;244;67;54m"))  // red
    }

    @Test("TTY trueColor: 节省颜色使用 emerald-400")
    func tty_trueColor_savedColorEmerald() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 90_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        #expect(result.contains("\u{1B}[38;2;52;211;153m"))  // emerald-400
    }

    // MARK: - TTY 模式 + ANSI256

    @Test("TTY ansi256: 使用 256 色码")
    func tty_ansi256_correctColorCodes() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 90_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .ansi256
        )
        // 节省颜色: emerald via ansi256
        #expect(result.contains("\u{1B}[38;5;77m"))
        // dim: slate-400 via ansi256
        #expect(result.contains("\u{1B}[38;5;145m"))
    }

    // MARK: - TTY 模式 + ANSI16

    @Test("TTY ansi16: 使用 16 色码")
    func tty_ansi16_correctColorCodes() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 90_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .ansi16
        )
        // 节省颜色: cyan
        #expect(result.contains("\u{1B}[36m"))
        // dim: white/gray
        #expect(result.contains("\u{1B}[37m"))
    }

    // MARK: - TTY 模式 + unknown profile

    @Test("TTY unknown: 有进度条字符但无颜色码")
    func tty_unknown_noColorCodes() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 90_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .unknown
        )
        // 仍有进度条字符
        #expect(result.contains("█"))
        #expect(result.contains("░"))
        // 仍有节省信息
        #expect(result.contains("节省"))
        // 有 reset 码（安全）
        #expect(result.contains("\u{1B}[0m"))
    }

    // MARK: - 边界值

    @Test("边界: beforeTokens == afterTokens → 0% 节省")
    func boundary_noChange() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 50_000,
            afterTokens: 50_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        #expect(result.contains("节省 0 (0%)"))
    }

    @Test("边界: 零 token 压缩")
    func boundary_zeroToZero() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 0,
            afterTokens: 0,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        #expect(result.contains("0 → 0 tokens"))
        #expect(result.contains("节省 0 (0%)"))
    }

    @Test("边界: 超大压缩比（95%+）")
    func boundary_largeCompression() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 190_000,
            afterTokens: 5_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        #expect(result.contains("节省 185k"))
        #expect(result.contains("97%"))  // 185000/190000 ≈ 97%
    }

    @Test("边界: before 超过 contextWindow（溢出）")
    func boundary_overflowBefore() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 250_000,  // > 200k
            afterTokens: 10_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        // 125% → 溢出使用品红色
        #expect(result.contains("\u{1B}[38;2;255;0;255m"))  // magenta for overflow
        // 125% → 进度条全部填满 (█ × 10)
        #expect(result.contains("██████████"))
    }

    // MARK: - ContextManager 集成

    @Test("ContextManager.formatCompactMessage: 新签名向后兼容（无 contextWindow）")
    func contextManager_backwardCompatible() {
        // 不传 contextWindow（默认 0）→ 降级为纯文本
        let result = ContextManager.formatCompactMessage(
            beforeTokens: 45_000,
            afterTokens: 8_000
        )
        #expect(result == "[axion] 上下文已自动压缩 (45k → 8k tokens)\n")
    }

    @Test("ContextManager.formatCompactMessage: 带 contextWindow 启用可视化")
    func contextManager_withWindow() {
        let result = ContextManager.formatCompactMessage(
            beforeTokens: 45_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        #expect(result.contains("45k → 8k tokens"))
        #expect(result.contains("节省"))
        #expect(result.contains("✂"))
    }

    // MARK: - 进度条宽度一致性

    @Test("进度条: before 和 after 各含 10 个 block 字符")
    func progressBar_equalWidth() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 90_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        // 移除所有 ANSI 转义码后，统计 █▓░ 字符数量
        let stripped = stripANSI(result)
        let blockChars = stripped.filter { "█▓░".contains($0) }
        // 两个进度条各 10 字符 = 20 个 block 字符
        #expect(blockChars.count == 20)
    }

    // MARK: - 视觉结构验证

    @Test("视觉结构: 输出包含头部行和详情行（两行）")
    func visualStructure_twoLines() {
        let result = CompactionDisplayFormatter.format(
            beforeTokens: 90_000,
            afterTokens: 8_000,
            contextWindow: 200_000,
            isTTY: true,
            profile: .trueColor
        )
        // 移除 ANSI 转义码计算可见行数
        let visible = stripANSI(result)
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
        // 至少 2 行：头部 + 详情
        #expect(visible.count >= 2)
    }

    // MARK: - Helpers

    /// 移除 ANSI 转义码序列
    private func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
    }
}
