import Foundation
import Testing

@testable import AxionCLI

@Suite("ClipboardService")
struct ClipboardServiceTests {

    // MARK: - Environment Detection

    @Test("Environment.detect: 非 SSH 非 tmux")
    func environment_local() {
        let env = ClipboardService.Environment.detect(env: [:])
        #expect(!env.isSSHSession)
        #expect(!env.isTmuxSession)
    }

    @Test("Environment.detect: SSH_TTY 设置")
    func environment_ssh() {
        let env = ClipboardService.Environment.detect(env: ["SSH_TTY": "/dev/pts/0"])
        #expect(env.isSSHSession)
        #expect(!env.isTmuxSession)
    }

    @Test("Environment.detect: SSH_CONNECTION 设置")
    func environment_sshConnection() {
        let env = ClipboardService.Environment.detect(env: ["SSH_CONNECTION": "10.0.0.1 12345 10.0.0.2 22"])
        #expect(env.isSSHSession)
    }

    @Test("Environment.detect: tmux TMUX 设置")
    func environment_tmux() {
        let env = ClipboardService.Environment.detect(env: ["TMUX": "/tmp/tmux-1000/default,12345,0"])
        #expect(!env.isSSHSession)
        #expect(env.isTmuxSession)
    }

    @Test("Environment.detect: tmux TMUX_PANE 设置")
    func environment_tmuxPane() {
        let env = ClipboardService.Environment.detect(env: ["TMUX_PANE": "%1"])
        #expect(env.isTmuxSession)
    }

    @Test("Environment.detect: SSH + tmux")
    func environment_sshTmux() {
        let env = ClipboardService.Environment.detect(env: [
            "SSH_CONNECTION": "10.0.0.1 12345 10.0.0.2 22",
            "TMUX": "/tmp/tmux-1000/default,12345,0",
        ])
        #expect(env.isSSHSession)
        #expect(env.isTmuxSession)
    }

    // MARK: - copy: Local Session (pbcopy first)

    @Test("copy: 本地会话优先使用 pbcopy")
    func copy_localPrefersPbcopy() {
        var pbcopyCalled = false
        let result = ClipboardService.copy(
            text: "Hello, world!",
            env: ClipboardService.Environment(isSSHSession: false, isTmuxSession: false),
            pbcopyFn: { text in
                #expect(text == "Hello, world!")
                pbcopyCalled = true
                return true
            },
            osc52Fn: { _ in false },
            tmuxFn: { _ in false }
        )
        if case .success(let backend) = result {
            #expect(backend == "pbcopy")
            #expect(pbcopyCalled)
        } else {
            Issue.record("Expected success with pbcopy backend")
        }
    }

    @Test("copy: pbcopy 失败时降级到 OSC 52")
    func copy_localFallbackOSC52() {
        var osc52Called = false
        let result = ClipboardService.copy(
            text: "Fallback text",
            env: ClipboardService.Environment(isSSHSession: false, isTmuxSession: false),
            pbcopyFn: { _ in false },
            osc52Fn: { text in
                #expect(text == "Fallback text")
                osc52Called = true
                return true
            },
            tmuxFn: { _ in false }
        )
        if case .success(let backend) = result {
            #expect(backend == "osc52")
            #expect(osc52Called)
        } else {
            Issue.record("Expected success with osc52 backend")
        }
    }

    @Test("copy: pbcopy 和 OSC 52 都失败")
    func copy_localAllFail() {
        let result = ClipboardService.copy(
            text: "Test",
            env: ClipboardService.Environment(isSSHSession: false, isTmuxSession: false),
            pbcopyFn: { _ in false },
            osc52Fn: { _ in false },
            tmuxFn: { _ in false }
        )
        if case .failure(let error) = result {
            #expect(error.contains("OSC 52"))
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - copy: SSH Session (terminal-mediated first)

    @Test("copy: SSH 会话使用 OSC 52")
    func copy_sshUsesOSC52() {
        var osc52Called = false
        let result = ClipboardService.copy(
            text: "SSH text",
            env: ClipboardService.Environment(isSSHSession: true, isTmuxSession: false),
            pbcopyFn: { _ in true },  // pbcopy 不应被调用
            osc52Fn: { text in
                #expect(text == "SSH text")
                osc52Called = true
                return true
            },
            tmuxFn: { _ in false }
        )
        if case .success(let backend) = result {
            #expect(backend == "osc52")
            #expect(osc52Called)
        } else {
            Issue.record("Expected success with osc52 backend")
        }
    }

    // MARK: - copy: SSH + tmux Session

    @Test("copy: SSH + tmux 优先使用 tmux 剪贴板")
    func copy_sshTmuxPrefersTmux() {
        var tmuxCalled = false
        let result = ClipboardService.copy(
            text: "tmux text",
            env: ClipboardService.Environment(isSSHSession: true, isTmuxSession: true),
            pbcopyFn: { _ in true },  // 不应调用
            osc52Fn: { _ in true },   // 不应调用
            tmuxFn: { text in
                #expect(text == "tmux text")
                tmuxCalled = true
                return true
            }
        )
        if case .success(let backend) = result {
            #expect(backend == "tmux")
            #expect(tmuxCalled)
        } else {
            Issue.record("Expected success with tmux backend")
        }
    }

    @Test("copy: tmux 失败时降级到 OSC 52")
    func copy_sshTmuxFallbackOSC52() {
        var osc52Called = false
        let result = ClipboardService.copy(
            text: "tmux fallback",
            env: ClipboardService.Environment(isSSHSession: true, isTmuxSession: true),
            pbcopyFn: { _ in true },
            osc52Fn: { text in
                #expect(text == "tmux fallback")
                osc52Called = true
                return true
            },
            tmuxFn: { _ in false }
        )
        if case .success(let backend) = result {
            #expect(backend == "osc52")
            #expect(osc52Called)
        } else {
            Issue.record("Expected success with osc52 backend")
        }
    }

    @Test("copy: SSH + tmux 全部失败")
    func copy_sshTmuxAllFail() {
        let result = ClipboardService.copy(
            text: "Test",
            env: ClipboardService.Environment(isSSHSession: true, isTmuxSession: true),
            pbcopyFn: { _ in true },
            osc52Fn: { _ in false },
            tmuxFn: { _ in false }
        )
        if case .failure(let error) = result {
            #expect(error.contains("tmux"))
            #expect(error.contains("OSC 52"))
        } else {
            Issue.record("Expected failure")
        }
    }

    // MARK: - copy: Edge Cases

    @Test("copy: 空文本返回失败")
    func copy_emptyText() {
        let result = ClipboardService.copy(
            text: "",
            env: ClipboardService.Environment(isSSHSession: false, isTmuxSession: false),
            pbcopyFn: { _ in true },
            osc52Fn: { _ in true },
            tmuxFn: { _ in true }
        )
        if case .failure(let error) = result {
            #expect(error.contains("没有可复制的内容"))
        } else {
            Issue.record("Expected failure for empty text")
        }
    }

    @Test("copy: 多行文本正确传递")
    func copy_multilineText() {
        let multiline = "Line 1\nLine 2\nLine 3"
        var capturedText = ""
        let _ = ClipboardService.copy(
            text: multiline,
            env: ClipboardService.Environment(isSSHSession: false, isTmuxSession: false),
            pbcopyFn: { text in capturedText = text; return true },
            osc52Fn: { _ in false },
            tmuxFn: { _ in false }
        )
        #expect(capturedText == multiline)
    }

    @Test("copy: Unicode/CJK 文本正确传递")
    func copy_unicodeText() {
        let unicode = "你好世界 🌍 日本語テスト 한국어"
        var capturedText = ""
        let _ = ClipboardService.copy(
            text: unicode,
            env: ClipboardService.Environment(isSSHSession: false, isTmuxSession: false),
            pbcopyFn: { text in capturedText = text; return true },
            osc52Fn: { _ in false },
            tmuxFn: { _ in false }
        )
        #expect(capturedText == unicode)
    }

    // MARK: - OSC 52 Sequence

    @Test("osc52Sequence: 生成标准序列")
    func osc52Sequence_standard() {
        let seq = ClipboardService.osc52Sequence(text: "hello", isTmux: false)
        #expect(seq != nil)
        #expect(seq!.hasPrefix("\u{1B}]52;c;"))
        #expect(seq!.hasSuffix("\u{07}"))
        // base64 of "hello" is "aGVsbG8="
        #expect(seq!.contains("aGVsbG8="))
    }

    @Test("osc52Sequence: tmux DCS passthrough 包装")
    func osc52Sequence_tmux() {
        let seq = ClipboardService.osc52Sequence(text: "hello", isTmux: true)
        #expect(seq != nil)
        // tmux passthrough: \ePtmux;\e\e]52;c;BASE64\a\e\\
        #expect(seq!.hasPrefix("\u{1B}Ptmux;\u{1B}\u{1B}]52;c;"))
        #expect(seq!.hasSuffix("\u{07}\u{1B}\\"))
    }

    @Test("osc52Sequence: 大载荷返回 nil")
    func osc52Sequence_tooLarge() {
        let largeText = String(repeating: "x", count: ClipboardService.osc52MaxBytes + 1)
        let seq = ClipboardService.osc52Sequence(text: largeText, isTmux: false)
        #expect(seq == nil)
    }

    @Test("osc52Sequence: 空文本生成有效序列")
    func osc52Sequence_empty() {
        let seq = ClipboardService.osc52Sequence(text: "", isTmux: false)
        #expect(seq != nil)
        // base64 of "" is ""
        #expect(seq!.contains("\u{1B}]52;c;\u{07}"))
    }

    @Test("osc52Sequence: 恰好上限大小的文本成功")
    func osc52Sequence_exactMaxSize() {
        let exactText = String(repeating: "a", count: ClipboardService.osc52MaxBytes)
        let seq = ClipboardService.osc52Sequence(text: exactText, isTmux: false)
        #expect(seq != nil)
    }

    @Test("osc52Sequence: Unicode 文本正确编码")
    func osc52Sequence_unicode() {
        let seq = ClipboardService.osc52Sequence(text: "你好", isTmux: false)
        #expect(seq != nil)
        // 验证 base64 可解码回原文
        if let seq,
           let encodedStart = seq.range(of: ";c;"),
           let encodedEnd = seq.range(of: "\u{07}", range: encodedStart.upperBound..<seq.endIndex) {
            let encoded = String(seq[encodedStart.upperBound..<encodedEnd.lowerBound])
            if let data = Data(base64Encoded: encoded),
               let decoded = String(data: data, encoding: .utf8) {
                #expect(decoded == "你好")
            } else {
                Issue.record("Failed to decode base64")
            }
        }
    }

    // MARK: - Format Helpers

    @Test("formatSuccess: 包含后端名和字符数")
    func formatSuccess() {
        let msg = ClipboardService.formatSuccess(backend: "pbcopy", charCount: 42)
        #expect(msg.contains("pbcopy"))
        #expect(msg.contains("42"))
        #expect(msg.contains("📋"))
    }

    @Test("formatFailure: 包含错误信息")
    func formatFailure() {
        let msg = ClipboardService.formatFailure("some error")
        #expect(msg.contains("some error"))
        #expect(msg.contains("❌"))
    }

    @Test("formatNoContent: 提示无内容")
    func formatNoContent() {
        let msg = ClipboardService.formatNoContent()
        #expect(msg.contains("没有可复制的内容"))
    }

    // MARK: - handleCopy

    @Test("handleCopy: 成功复制")
    func handleCopy_success() {
        let output = SlashCommandHandler.handleCopy(
            lastAssistantText: "Hello from assistant",
            copyFn: { _ in .success(backend: "mock-backend") }
        )
        #expect(output.contains("📋"))
        #expect(output.contains("mock-backend"))
    }

    @Test("handleCopy: 空文本")
    func handleCopy_empty() {
        let output = SlashCommandHandler.handleCopy(
            lastAssistantText: "",
            copyFn: { _ in .success(backend: "mock") }
        )
        #expect(output.contains("没有可复制的内容"))
    }

    @Test("handleCopy: 复制失败")
    func handleCopy_failure() {
        let output = SlashCommandHandler.handleCopy(
            lastAssistantText: "Some text",
            copyFn: { _ in .failure("mock failure") }
        )
        #expect(output.contains("❌"))
        #expect(output.contains("mock failure"))
    }

    @Test("handleCopy: 传递正确的文本到 copyFn")
    func handleCopy_passesCorrectText() {
        var capturedText = ""
        let _ = SlashCommandHandler.handleCopy(
            lastAssistantText: "exact text",
            copyFn: { text in
                capturedText = text
                return .success(backend: "test")
            }
        )
        #expect(capturedText == "exact text")
    }

    @Test("handleCopy: 字符数正确显示")
    func handleCopy_charCount() {
        let text = "你好"  // 2 characters
        let output = SlashCommandHandler.handleCopy(
            lastAssistantText: text,
            copyFn: { _ in .success(backend: "test") }
        )
        #expect(output.contains("2 字符"))
    }
}
