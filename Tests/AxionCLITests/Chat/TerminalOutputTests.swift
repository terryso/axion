import Foundation
import OpenAgentSDK
import Testing

@testable import AxionCLI

// MARK: - ChatOutputFormatter Tests

@Suite("ChatOutputFormatter")
struct ChatOutputFormatterTests {

    // MARK: - Helper: 创建 capturing formatter

    private func makeFormatter() -> (ChatOutputFormatter, CaptureOutput, CaptureOutput) {
        let stdout = CaptureOutput()
        let stderr = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: false, writeStderr: { _ in })
        let formatter = ChatOutputFormatter(
            writeStdout: { stdout.write($0) },
            writeStderr: { stderr.write($0) },
            spinner: spinner
        )
        return (formatter, stdout, stderr)
    }

    // MARK: - Tool Use Format (AC #1)

    @Test("toolUse: 按类别显示工具标签和参数摘要")
    func toolUseFormat() {
        let (formatter, stdout, _) = makeFormatter()
        let toolUse = SDKMessage.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-1", input: "{\"command\":\"ls -la\"}")
        )
        formatter.handle(toolUse)
        let output = stdout.captured
        // Codex-inspired: 按类别显示 "exec" 标签而非通用 ⏳
        #expect(output.contains("exec"))
        #expect(output.contains("ls -la"))
    }

    // MARK: - Tool Result Format (AC #1)

    @Test("toolResult success: 显示 ✓ 完成标记")
    func toolResultSuccess() {
        let (formatter, stdout, _) = makeFormatter()

        // 先触发 toolUse 来设定开始时间
        let toolUse = SDKMessage.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-1", input: "{\"command\":\"ls\"}")
        )
        formatter.handle(toolUse)

        stdout.clear()

        let toolResult = SDKMessage.toolResult(
            .init(toolUseId: "tu-1", content: "file1.txt\nfile2.txt", isError: false)
        )
        formatter.handle(toolResult)
        let output = stdout.captured
        // Codex-inspired: ✓ 标记（而非 ✅）
        #expect(output.contains("✓"))
        #expect(output.contains("file1.txt"))
    }

    @Test("toolResult error: 显示 ✗ 错误标记")
    func toolResultError() {
        let (formatter, stdout, _) = makeFormatter()

        let toolUse = SDKMessage.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-2", input: "{\"command\":\"bad_cmd\"}")
        )
        formatter.handle(toolUse)

        stdout.clear()

        let toolResult = SDKMessage.toolResult(
            .init(toolUseId: "tu-2", content: "command not found", isError: true)
        )
        formatter.handle(toolResult)
        let output = stdout.captured
        // Codex-inspired: ✗ 标记（而非 ❌）
        #expect(output.contains("✗"))
        #expect(output.contains("command not found"))
    }

    // MARK: - LLM Text Output (AC #2)

    @Test("partialMessage: 直接输出，无 [axion] 前缀")
    func partialMessageNoPrefix() {
        let (formatter, stdout, _) = makeFormatter()
        let partial = SDKMessage.partialMessage(.init(text: "Hello, "))
        formatter.handle(partial)
        let output = stdout.captured
        #expect(output == "Hello, ")
        #expect(!output.contains("[axion]"))
    }

    // MARK: - Separator (AC #2)

    @Test("LLM text and toolUse separated by blank line")
    func separatorBetweenTextAndToolUse() {
        let (formatter, stdout, _) = makeFormatter()

        // LLM 文本
        formatter.handle(.partialMessage(.init(text: "Let me check")))
        // assistant 结束
        formatter.handle(.assistant(.init(text: "Let me check", model: "test", stopReason: "tool_use")))

        stdout.clear()

        // 工具调用
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-3", input: "{\"command\":\"ls\"}")
        ))

        // 应在工具调用前有空行分隔
        let output = stdout.captured
        // Codex-inspired: 类别标签格式（非 ⏳）
        #expect(output.hasPrefix("\n"))
        #expect(output.contains("exec"))
    }

    // MARK: - Screenshot Detection

    @Test("toolResult: screenshot 完成显示 ✓ 标记")
    func screenshotResultSummarized() {
        let (formatter, stdout, _) = makeFormatter()

        formatter.handle(.toolUse(
            .init(toolName: "Screenshot", toolUseId: "tu-4", input: "{}")
        ))
        stdout.clear()

        formatter.handle(.toolResult(
            .init(toolUseId: "tu-4", content: "{\"action\":\"screenshot\",\"image_data\":\"...\"}", isError: false)
        ))
        let output = stdout.captured
        // Codex-inspired: ✓ 标记代替旧的 ✅
        #expect(output.contains("✓"))
    }

    // MARK: - Result Status

    @Test("result errorMaxTurns: 显示 ⚠️ 提示")
    func resultErrorMaxTurns() {
        let (_, _, _) = makeFormatter()
        let stderr = CaptureOutput()
        let formatter2 = ChatOutputFormatter(
            writeStdout: { _ in },
            writeStderr: { stderr.write($0) },
            spinner: SpinnerRenderer(isTTY: false, writeStderr: { _ in })
        )

        formatter2.handle(.result(
            .init(subtype: .errorMaxTurns, text: "", usage: nil, numTurns: 10, durationMs: 5000)
        ))
        let output = stderr.captured
        #expect(output.contains("⚠️"))
        #expect(output.contains("最大步数限制"))
    }

    // MARK: - LLM Wait Spinner (AC #3)

    @Test("startLLMWaiting: 启动延迟 spinner 后 partialMessage 停止 spinner")
    func startLLMWaitingThenPartialMessage() {
        let stdout = CaptureOutput()
        let stderr = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: false, writeStderr: { stderr.write($0) })
        let formatter = ChatOutputFormatter(
            writeStdout: { stdout.write($0) },
            writeStderr: { stderr.write($0) },
            spinner: spinner
        )

        // 启动 LLM 等待（非 TTY spinner 不会真正输出，但流程正确）
        formatter.startLLMWaiting()

        // 收到 partialMessage → spinner 停止
        formatter.handle(.partialMessage(.init(text: "Hello")))

        #expect(stdout.captured == "Hello")
    }

    @Test("toolResult 后启动 LLM 等待 spinner")
    func toolResultTriggersLLMWaitSpinner() {
        let (formatter, stdout, _) = makeFormatter()

        // 先 toolUse
        formatter.handle(.toolUse(
            .init(toolName: "Bash", toolUseId: "tu-5", input: "{\"command\":\"ls\"}")
        ))
        stdout.clear()

        // toolResult 后应启动 LLM 等待（非 TTY 不输出，验证流程不崩溃）
        formatter.handle(.toolResult(
            .init(toolUseId: "tu-5", content: "file.txt", isError: false)
        ))

        #expect(stdout.captured.contains("✓"))

        // 然后收到 partialMessage → spinner 停止（无崩溃）
        formatter.handle(.partialMessage(.init(text: "Done!")))
        #expect(stdout.captured.contains("Done!"))
    }
}

// MARK: - SpinnerRenderer Tests

@Suite("SpinnerRenderer")
struct SpinnerRendererTests {

    @Test("非 TTY 时不输出 spinner")
    func nonTTYNoOutput() {
        let output = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: false, writeStderr: { output.write($0) })

        spinner.start(message: "test")
        // 给一点时间让 timer 触发（虽然不应该）
        Thread.sleep(forTimeInterval: 0.1)
        spinner.stop()

        // 非 TTY 模式不应有任何输出
        #expect(output.captured.isEmpty)
    }

    @Test("stop 在非 TTY 时不输出清除码")
    func stopNonTTYNOClear() {
        let output = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: false, writeStderr: { output.write($0) })

        spinner.stop()
        #expect(output.captured.isEmpty)
    }

    @Test("TTY 模式：启动后 stop 清除 spinner 行")
    func ttyStopClearsLineAfterStart() {
        let output = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: true, writeStderr: { output.write($0) })

        // 启动 spinner（无延迟）
        spinner.start(message: "test")
        Thread.sleep(forTimeInterval: 0.15)  // 等待至少一帧
        output.clear()  // 清除 spinner 帧输出，只观察 stop 输出

        spinner.stop()
        #expect(output.captured.contains("\r\033[K"))
    }

    @Test("TTY 模式：无活跃 spinner 时 stop 不输出清除码")
    func ttyStopNoClearWithoutActiveSpinner() {
        let output = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: true, writeStderr: { output.write($0) })

        // 从未启动，直接 stop
        spinner.stop()
        #expect(!output.captured.contains("\r\033[K"))
    }

    @Test("delayed start: 延迟期间无输出，延迟后开始动画")
    func delayedStart() {
        let output = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: true, writeStderr: { output.write($0) })

        spinner.start(message: "thinking", delayMs: 200)

        // 立即检查 — 延迟期间不应有输出
        Thread.sleep(forTimeInterval: 0.05)
        #expect(!output.captured.contains("⏳"))

        // 等待延迟过期 + 至少一帧
        Thread.sleep(forTimeInterval: 0.3)
        #expect(output.captured.contains("⏳"))
        #expect(output.captured.contains("thinking"))

        spinner.stop()
    }

    @Test("stop 取消延迟 spinner，动画从未启动则不输出清除码")
    func stopCancelsDelayedStart() {
        let output = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: true, writeStderr: { output.write($0) })

        spinner.start(message: "test", delayMs: 500)
        Thread.sleep(forTimeInterval: 0.1)
        spinner.stop()

        // 延迟期间被取消，动画从未启动，不应有清除码
        #expect(!output.captured.contains("\r\033[K"))
        #expect(!output.captured.contains("⏳"))
    }

    @Test("TTY 模式：spinner 输出包含 braille frame 字符")
    func ttySpinnerOutputContainsBrailleFrames() {
        let output = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: true, writeStderr: { output.write($0) })

        spinner.start(message: "loading")
        Thread.sleep(forTimeInterval: 0.2)  // 等待几帧

        spinner.stop()

        let captured = output.captured
        // 应包含 ⏳ 前缀和 message
        #expect(captured.contains("⏳"))
        #expect(captured.contains("loading"))
        // 应包含至少一个 braille frame
        let brailleChars = CharacterSet(charactersIn: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
        #expect(captured.unicodeScalars.contains(where: { brailleChars.contains($0) }))
    }

    @Test("TTY 模式：spinner 输出包含实时耗时")
    func ttySpinnerOutputContainsElapsedTime() {
        let output = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: true, writeStderr: { output.write($0) })

        spinner.start(message: "thinking")
        Thread.sleep(forTimeInterval: 0.25)  // 等待几帧

        spinner.stop()

        let captured = output.captured
        // 应包含耗时格式 "X.Xs"
        let elapsedPattern = Regex(/[0-9]+\.[0-9]s/)
        #expect(captured.contains(elapsedPattern))
        #expect(captured.contains("thinking"))
    }

    @Test("专用 Thread 在 cooperative 池阻塞负载下持续 tick（模拟 storage_scan）")
    func dedicatedThreadTicksUnderCooperativePoolBlockingLoad() async throws {
        let output = CaptureOutput()
        let spinner = SpinnerRenderer(isTTY: true, writeStderr: { output.write($0) })

        spinner.start(message: "storage_scan", delayMs: 0)

        // 模拟扫描：在 cooperative 池上做阻塞系统调用（usleep），触发 Swift 阻塞检测 → 池膨胀，
        // 复现 storage_scan 饿死旧 GCD 定时器的场景。
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<100 { usleep(5_000) }  // 100 × 5ms 阻塞 ≈ 500ms/任务
                }
            }
        }

        spinner.stop()

        // 每帧写一个 ⏳；若 spinner 持续 tick，⏳ 计数应 ≥ 3（工作 spinner ≈ 8 帧；饿死 = 1 帧）。
        let frameCount = output.captured.components(separatedBy: "⏳").count - 1
        #expect(frameCount >= 3, "spinner 在阻塞负载下冻结；帧数 = \(frameCount)")
    }
}

// MARK: - SpinnerRenderer.formatElapsedMs Tests

@Suite("SpinnerRenderer.formatElapsedMs")
struct SpinnerFormatElapsedMsTests {

    @Test("小于 1 秒显示小数格式")
    func subSecond() {
        #expect(SpinnerRenderer.formatElapsedMs(300) == "0.3s")
        #expect(SpinnerRenderer.formatElapsedMs(50) == "0.1s")
        #expect(SpinnerRenderer.formatElapsedMs(999) == "1.0s")
    }

    @Test("1-59 秒显示秒格式")
    func seconds() {
        #expect(SpinnerRenderer.formatElapsedMs(1200) == "1.2s")
        #expect(SpinnerRenderer.formatElapsedMs(12300) == "12.3s")
        #expect(SpinnerRenderer.formatElapsedMs(59999) == "60.0s")
    }

    @Test("60 秒以上显示分秒格式")
    func minutesSeconds() {
        #expect(SpinnerRenderer.formatElapsedMs(60_000) == "1m 00s")
        #expect(SpinnerRenderer.formatElapsedMs(122_000) == "2m 02s")
        #expect(SpinnerRenderer.formatElapsedMs(3599_000) == "59m 59s")
    }

    @Test("1 小时以上显示时分秒格式")
    func hoursMinutesSeconds() {
        #expect(SpinnerRenderer.formatElapsedMs(3_600_000) == "1h 00m 00s")
        #expect(SpinnerRenderer.formatElapsedMs(3_723_000) == "1h 02m 03s")
        #expect(SpinnerRenderer.formatElapsedMs(7_380_000) == "2h 03m 00s")
    }

    @Test("0 毫秒显示 0.0s")
    func zeroMs() {
        #expect(SpinnerRenderer.formatElapsedMs(0) == "0.0s")
    }
}

// MARK: - Capture Output Helper

final class CaptureOutput: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()

    func write(_ text: String) {
        lock.lock()
        buffer += text
        lock.unlock()
    }

    var captured: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func clear() {
        lock.lock()
        buffer = ""
        lock.unlock()
    }
}
