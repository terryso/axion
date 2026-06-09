import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

// [P1] 行为验证 — ChatOutputFormatter 集成 TranscriptRenderer 后的角色标识
// TDD RED PHASE: 测试引用尚未实现的 ChatTheme 集成

@Suite("ChatOutputFormatter + TranscriptRenderer 集成")
struct TranscriptIntegrationTests {

    // MARK: - Helper: 创建带 ChatTheme 的 formatter

    private func makeThemedFormatter(
        profile: TerminalColorProfile = .ansi16,
        isTTY: Bool = true
    ) -> (ChatOutputFormatter, CaptureOutput, CaptureOutput) {
        let stdout = CaptureOutput()
        let stderr = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: false, writeStderr: { _ in })
        let theme = ChatTheme(profile: profile, isTTY: isTTY)
        let formatter = ChatOutputFormatter(
            writeStdout: { stdout.write($0) },
            writeStderr: { stderr.write($0) },
            spinner: spinner,
            theme: theme
        )
        return (formatter, stdout, stderr)
    }

    // MARK: - toolUse 角色标识 (AC3)

    @Test("toolUse: TTY 模式输出包含黄色圆点角色标识")
    func toolUse_yellowDot() {
        let (formatter, stdout, _) = makeThemedFormatter(profile: .ansi16, isTTY: true)
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-1", input: "{\"command\":\"ls\"}")
        ))
        let output = stdout.captured
        // 应包含黄色圆点 ANSI 码
        #expect(output.contains("\u{1B}[33m"))
        // 仍包含工具名
        #expect(output.contains("Bash"))
        // 仍包含 ⏳ 图标（增量添加，不替换）
        #expect(output.contains("⏳"))
    }

    @Test("toolUse: 非 TTY 模式输出 [tool] 纯文本前缀")
    func toolUse_plainText() {
        let (formatter, stdout, _) = makeThemedFormatter(profile: .unknown, isTTY: false)
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-1", input: "{\"command\":\"ls\"}")
        ))
        let output = stdout.captured
        #expect(output.contains("[tool]"))
        #expect(output.contains("Bash"))
    }

    // MARK: - toolResult 角色标识 (AC3)

    @Test("toolResult success: TTY 模式输出包含黄色圆点")
    func toolResult_success_yellowDot() {
        let (formatter, stdout, _) = makeThemedFormatter(profile: .ansi16, isTTY: true)
        // 先触发 toolUse
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-1", input: "{\"command\":\"ls\"}")
        ))
        stdout.clear()

        formatter.handle(.toolResult(
            .init(toolUseId: "tu-1", content: "file.txt", isError: false)
        ))
        let output = stdout.captured
        #expect(output.contains("\u{1B}[33m"))
        #expect(output.contains("✅"))
    }

    @Test("toolResult error: TTY 模式输出包含红色圆点")
    func toolResult_error_redDot() {
        let (formatter, stdout, _) = makeThemedFormatter(profile: .ansi16, isTTY: true)
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-2", input: "{\"command\":\"bad\"}")
        ))
        stdout.clear()

        formatter.handle(.toolResult(
            .init(toolUseId: "tu-2", content: "error", isError: true)
        ))
        let output = stdout.captured
        #expect(output.contains("\u{1B}[31m"))
        #expect(output.contains("❌"))
    }

    // MARK: - result 状态角色标识 (AC3)

    @Test("result errorMaxTurns: TTY 模式输出包含红色圆点")
    func result_errorMaxTurns_redDot() {
        let (_, _, stderr) = makeThemedFormatter(profile: .ansi16, isTTY: true)
        let stdout = CaptureOutput()
        let formatter2 = ChatOutputFormatter(
            writeStdout: { stdout.write($0) },
            writeStderr: { stderr.write($0) },
            spinner: SpinnerRenderer(isTTY: false, writeStderr: { _ in }),
            theme: ChatTheme(profile: .ansi16, isTTY: true)
        )
        formatter2.handle(.result(
            .init(subtype: .errorMaxTurns, text: "", usage: nil as TokenUsage?, numTurns: 10, durationMs: 5000)
        ))
        let output = stderr.captured
        #expect(output.contains("\u{1B}[31m"))
        #expect(output.contains("最大步数"))
    }

    @Test("result errorMaxTurns: 非 TTY 使用 [warn] 纯文本")
    func result_errorMaxTurns_plainText() {
        let (_, _, stderr) = makeThemedFormatter(profile: .unknown, isTTY: false)
        let stdout = CaptureOutput()
        let formatter2 = ChatOutputFormatter(
            writeStdout: { stdout.write($0) },
            writeStderr: { stderr.write($0) },
            spinner: SpinnerRenderer(isTTY: false, writeStderr: { _ in }),
            theme: ChatTheme(profile: .unknown, isTTY: false)
        )
        formatter2.handle(.result(
            .init(subtype: .errorMaxTurns, text: "", usage: nil as TokenUsage?, numTurns: 10, durationMs: 5000)
        ))
        let output = stderr.captured
        #expect(output.contains("[warn]"))
    }

    // MARK: - paused 状态角色标识 (AC3)

    @Test("system paused: TTY 模式输出包含红色圆点")
    func system_paused_redDot() {
        let (formatter, _, stderr) = makeThemedFormatter(profile: .ansi16, isTTY: true)
        formatter.handle(.system(.init(
            subtype: .paused,
            message: "paused",
            pausedData: .init(reason: "需要用户操作")
        )))
        let output = stderr.captured
        #expect(output.contains("\u{1B}[31m"))
    }

    // MARK: - 向后兼容（增量添加，不破坏现有图标）

    @Test("toolUse: 集成后仍保留 ⏳ 图标")
    func toolUse_retainsHourglassIcon() {
        let (formatter, stdout, _) = makeThemedFormatter(profile: .ansi16, isTTY: true)
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-1", input: "{\"command\":\"ls\"}")
        ))
        #expect(stdout.captured.contains("⏳"))
    }

    @Test("toolResult success: 集成后仍保留 ✅ 图标")
    func toolResult_retainsCheckIcon() {
        let (formatter, stdout, _) = makeThemedFormatter(profile: .ansi16, isTTY: true)
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-1", input: "{\"command\":\"ls\"}")
        ))
        stdout.clear()
        formatter.handle(.toolResult(
            .init(toolUseId: "tu-1", content: "ok", isError: false)
        ))
        #expect(stdout.captured.contains("✅"))
    }

    @Test("toolResult error: 集成后仍保留 ❌ 图标")
    func toolResult_retainsCrossIcon() {
        let (formatter, stdout, _) = makeThemedFormatter(profile: .ansi16, isTTY: true)
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-2", input: "{\"command\":\"bad\"}")
        ))
        stdout.clear()
        formatter.handle(.toolResult(
            .init(toolUseId: "tu-2", content: "fail", isError: true)
        ))
        #expect(stdout.captured.contains("❌"))
    }

    // MARK: - 无主题（nil theme）向后兼容

    @Test("无 ChatTheme 时 formatter 仍正常工作（向后兼容）")
    func noTheme_backwardCompatible() {
        let stdout = CaptureOutput()
        let stderr = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: false, writeStderr: { _ in })
        // 不传 theme（使用默认 nil）
        let formatter = ChatOutputFormatter(
            writeStdout: { stdout.write($0) },
            writeStderr: { stderr.write($0) },
            spinner: spinner
        )
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-1", input: "{\"command\":\"ls\"}")
        ))
        let output = stdout.captured
        #expect(output.contains("⏳"))
        #expect(output.contains("Bash"))
    }
}
