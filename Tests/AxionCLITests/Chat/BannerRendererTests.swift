import Foundation
import Testing

@testable import AxionCLI

@Suite("BannerRenderer")
struct BannerRendererTests {

    // MARK: - formatTokenCount

    @Test("formatTokenCount: 0 → \"0\"")
    func formatTokenCount_zero() {
        #expect(BannerRenderer.formatTokenCount(0) == "0")
    }

    @Test("formatTokenCount: 500 → \"500\"")
    func formatTokenCount_hundreds() {
        #expect(BannerRenderer.formatTokenCount(500) == "500")
    }

    @Test("formatTokenCount: 999 → \"999\"")
    func formatTokenCount_999() {
        #expect(BannerRenderer.formatTokenCount(999) == "999")
    }

    @Test("formatTokenCount: 1000 → \"1k\"")
    func formatTokenCount_exact1k() {
        #expect(BannerRenderer.formatTokenCount(1_000) == "1k")
    }

    @Test("formatTokenCount: 3200 → \"3.2k\"")
    func formatTokenCount_kWithDecimal() {
        #expect(BannerRenderer.formatTokenCount(3_200) == "3.2k")
    }

    @Test("formatTokenCount: 200000 → \"200k\"")
    func formatTokenCount_exact200k() {
        #expect(BannerRenderer.formatTokenCount(200_000) == "200k")
    }

    @Test("formatTokenCount: 999999 → \"1.0m\"")
    func formatTokenCount_999999() {
        #expect(BannerRenderer.formatTokenCount(999_999) == "1.0m")
    }

    @Test("formatTokenCount: 999949 → \"999.9k\" (k/m 边界)")
    func formatTokenCount_kmBoundary() {
        #expect(BannerRenderer.formatTokenCount(999_949) == "999.9k")
    }

    @Test("formatTokenCount: 1000000 → \"1m\"")
    func formatTokenCount_exact1m() {
        #expect(BannerRenderer.formatTokenCount(1_000_000) == "1m")
    }

    @Test("formatTokenCount: 1500000 → \"1.5m\"")
    func formatTokenCount_mWithDecimal() {
        #expect(BannerRenderer.formatTokenCount(1_500_000) == "1.5m")
    }

    // MARK: - renderBanner

    @Test("renderBanner 包含版本号、模型、CWD、sessionId")
    func renderBanner_containsKeyInfo() {
        let banner = BannerRenderer.renderBanner(
            version: "0.11.0",
            model: "claude-sonnet-4-6",
            cwd: "/Users/nick/project",
            sessionId: "chat-a3f8b2c1",
            contextWindow: 200_000,
            buildTimeMs: 157
        )
        #expect(banner.contains("Axion v0.11.0"))
        #expect(banner.contains("claude-sonnet-4-6"))
        #expect(banner.contains("/Users/nick/project"))
        #expect(banner.contains("chat-a3f8b2c1"))
        #expect(banner.contains("0/200k"))
        #expect(banner.contains("157ms"))
        #expect(banner.contains("/help"))
    }

    @Test("renderBanner 秒级耗时格式化")
    func renderBanner_buildTimeSeconds() {
        let banner = BannerRenderer.renderBanner(
            version: "1.0",
            model: "test-model",
            cwd: "/tmp",
            sessionId: "chat-abc12345",
            contextWindow: 200_000,
            buildTimeMs: 2345
        )
        #expect(banner.contains("2.3s"))
    }

    @Test("renderBanner 长路径被截断")
    func renderBanner_longCwdTruncated() {
        let longPath = "/Users/nick/very/deeply/nested/directory/structure/that/exceeds/max/length/limit/for/display"
        let banner = BannerRenderer.renderBanner(
            version: "1.0",
            model: "test",
            cwd: longPath,
            sessionId: "chat-test",
            contextWindow: 200_000,
            buildTimeMs: 100
        )
        // Banner should still render, path should be truncated with "…"
        #expect(banner.contains("…"))
        #expect(!banner.contains(longPath))
    }

    // MARK: - renderPrompt

    @Test("renderPrompt 零用量时显示 0/200k")
    func renderPrompt_zeroUsage() {
        let prompt = BannerRenderer.renderPrompt(usedTokens: 0, contextWindow: 200_000)
        #expect(prompt == "axion [0/200k]> ")
    }

    @Test("renderPrompt 有用量时显示正确格式")
    func renderPrompt_withUsage() {
        let prompt = BannerRenderer.renderPrompt(usedTokens: 3_200, contextWindow: 200_000)
        #expect(prompt == "axion [3.2k/200k]> ")
    }

    @Test("renderPrompt 百万级上下文窗口")
    func renderPrompt_largeContextWindow() {
        let prompt = BannerRenderer.renderPrompt(usedTokens: 0, contextWindow: 1_000_000)
        #expect(prompt == "axion [0/1m]> ")
    }

    // MARK: - renderExit

    @Test("renderExit 包含 sessionId 和恢复命令")
    func renderExit_containsSessionId() {
        let exit = BannerRenderer.renderExit(sessionId: "chat-a3f8b2c1")
        #expect(exit.contains("chat-a3f8b2c1"))
        #expect(exit.contains("/resume"))
    }

    @Test("renderExit 以换行结尾")
    func renderExit_endsWithNewline() {
        let exit = BannerRenderer.renderExit(sessionId: "chat-test")
        #expect(exit.hasSuffix("\n"))
    }
}
