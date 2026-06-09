import Foundation
import Testing

@testable import AxionCLI

@Suite("TerminalTitleRenderer")
struct TerminalTitleRendererTests {

    // MARK: - sanitize

    @Test("sanitize: 正常文本保持不变")
    func sanitize_normalText() {
        #expect(TerminalTitleRenderer.sanitize("Axion") == "Axion")
        #expect(TerminalTitleRenderer.sanitize("Axion ⏳ 思考中...") == "Axion ⏳ 思考中...")
    }

    @Test("sanitize: 移除控制字符")
    func sanitize_controlChars() {
        #expect(TerminalTitleRenderer.sanitize("Axion\u{01}\u{02}") == "Axion")
        #expect(TerminalTitleRenderer.sanitize("\u{00}Axion") == "Axion")
    }

    @Test("sanitize: 移除 C1 控制字符")
    func sanitize_c1ControlChars() {
        #expect(TerminalTitleRenderer.sanitize("Axion\u{80}\u{9F}") == "Axion")
    }

    @Test("sanitize: 移除 Bidi 控制字符")
    func sanitize_bidiChars() {
        #expect(TerminalTitleRenderer.sanitize("Axion\u{200E}\u{200F}") == "Axion")
        #expect(TerminalTitleRenderer.sanitize("Axion\u{202A}\u{202E}") == "Axion")
        #expect(TerminalTitleRenderer.sanitize("Axion\u{2066}\u{2069}") == "Axion")
    }

    @Test("sanitize: 移除 BOM")
    func sanitize_bom() {
        #expect(TerminalTitleRenderer.sanitize("\u{FEFF}Axion") == "Axion")
    }

    @Test("sanitize: 折叠连续空白")
    func sanitize_collapseWhitespace() {
        #expect(TerminalTitleRenderer.sanitize("Axion   thinking") == "Axion thinking")
        #expect(TerminalTitleRenderer.sanitize("  Axion  ") == "Axion")
    }

    @Test("sanitize: 截断超过 120 字符")
    func sanitize_truncateLong() {
        let long = String(repeating: "A", count: 200)
        let result = TerminalTitleRenderer.sanitize(long)
        #expect(result.count == 120)
    }

    @Test("sanitize: 空字符串保持为空")
    func sanitize_empty() {
        #expect(TerminalTitleRenderer.sanitize("") == "")
    }

    @Test("sanitize: 仅控制字符变空")
    func sanitize_onlyControlChars() {
        #expect(TerminalTitleRenderer.sanitize("\u{01}\u{02}\u{03}") == "")
    }

    // MARK: - setTitle (non-TTY skip)

    @Test("setTitle: 非 TTY 不输出任何内容")
    func setTitle_nonTTY() {
        var output = ""
        let renderer = TerminalTitleRenderer(isTTY: false) { output += $0 }
        renderer.setTitle("Axion")
        #expect(output.isEmpty)
    }

    // MARK: - setTitle (TTY)

    @Test("setTitle: TTY 输出 OSC 0 序列")
    func setTitle_tty() {
        var output = ""
        let renderer = TerminalTitleRenderer(isTTY: true) { output += $0 }
        renderer.setTitle("Axion")
        #expect(output == "\u{1B}]0;Axion\u{07}")
    }

    @Test("setIdle: 设置简洁标题")
    func setIdle() {
        var output = ""
        let renderer = TerminalTitleRenderer(isTTY: true) { output += $0 }
        renderer.setIdle()
        #expect(output == "\u{1B}]0;Axion\u{07}")
    }

    @Test("setThinking: 设置思考中标题")
    func setThinking() {
        var output = ""
        let renderer = TerminalTitleRenderer(isTTY: true) { output += $0 }
        renderer.setThinking()
        #expect(output == "\u{1B}]0;Axion ⏳ 思考中...\u{07}")
    }

    @Test("setThinking: 带耗时")
    func setThinkingWithElapsed() {
        var output = ""
        let renderer = TerminalTitleRenderer(isTTY: true) { output += $0 }
        renderer.setThinking(elapsed: "3.2s")
        #expect(output == "\u{1B}]0;Axion ⏳ 思考中 3.2s\u{07}")
    }

    @Test("setToolExecuting: 设置工具执行标题")
    func setToolExecuting() {
        var output = ""
        let renderer = TerminalTitleRenderer(isTTY: true) { output += $0 }
        renderer.setToolExecuting("bash")
        #expect(output == "\u{1B}]0;Axion ⏳ bash\u{07}")
    }

    @Test("setContextWarning: 设置上下文警告标题")
    func setContextWarning() {
        var output = ""
        let renderer = TerminalTitleRenderer(isTTY: true) { output += $0 }
        renderer.setContextWarning(pct: 85)
        #expect(output == "\u{1B}]0;Axion ⚠️ 85% context\u{07}")
    }

    @Test("clear: 清除标题")
    func clear() {
        var output = ""
        let renderer = TerminalTitleRenderer(isTTY: true) { output += $0 }
        renderer.clear()
        #expect(output == "\u{1B}]0;\u{07}")
    }

    @Test("clear: 非 TTY 不输出")
    func clear_nonTTY() {
        var output = ""
        let renderer = TerminalTitleRenderer(isTTY: false) { output += $0 }
        renderer.clear()
        #expect(output.isEmpty)
    }
}
