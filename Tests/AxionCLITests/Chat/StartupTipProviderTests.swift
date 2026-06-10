import Testing
import Foundation

@testable import AxionCLI

// MARK: - StartupTipProvider Tests

@Suite("StartupTipProvider Tests")
struct StartupTipProviderTests {

    // MARK: - First-run Detection

    @Test("isFirstRun returns true when history file does not exist")
    func isFirstRun_noHistoryFile() {
        let result = StartupTipProvider.isFirstRun(
            historyFilePath: "/nonexistent/path/history.jsonl",
            fileExists: { _ in false }
        )
        #expect(result == true)
    }

    @Test("isFirstRun returns false when history file exists")
    func isFirstRun_historyFileExists() {
        let result = StartupTipProvider.isFirstRun(
            historyFilePath: "/some/path/history.jsonl",
            fileExists: { _ in true }
        )
        #expect(result == false)
    }

    @Test("isFirstRun uses injected fileExists closure")
    func isFirstRun_injectedClosure() {
        var checkedPaths: [String] = []
        let result = StartupTipProvider.isFirstRun(
            historyFilePath: "/test/history.jsonl",
            fileExists: { path in
                checkedPaths.append(path)
                return path.contains("exists")
            }
        )
        #expect(result == true)  // "/test/history.jsonl" does not contain "exists"
        #expect(checkedPaths == ["/test/history.jsonl"])
    }

    // MARK: - Tip Selection

    @Test("getTip returns welcome message on first run")
    func getTip_firstRun() {
        let tip = StartupTipProvider.getTip(isFirstRun: true)
        #expect(tip == StartupTipProvider.firstRunWelcome)
        #expect(tip.contains("欢迎"))
    }

    @Test("getTip returns a tip from the pool on subsequent runs")
    func getTip_subsequentRun() {
        let tip = StartupTipProvider.getTip(isFirstRun: false, tipIndex: 0)
        #expect(StartupTipProvider.allTips.contains(tip))
    }

    @Test("getTip with tipIndex wraps around the pool")
    func getTip_tipIndexWraps() {
        let count = StartupTipProvider.allTips.count
        let tip0 = StartupTipProvider.getTip(isFirstRun: false, tipIndex: 0)
        let tipCount = StartupTipProvider.getTip(isFirstRun: false, tipIndex: count)
        #expect(tip0 == tipCount)  // index % count == 0 in both cases
    }

    @Test("getTip with tipIndex covers all tips")
    func getTip_tipIndexCoversAll() {
        var seen = Set<String>()
        let count = StartupTipProvider.allTips.count
        for i in 0..<count {
            let tip = StartupTipProvider.getTip(isFirstRun: false, tipIndex: i)
            seen.insert(tip)
        }
        #expect(seen.count == count)  // All tips are distinct and all are reachable
    }

    @Test("getTip with randomRange uses the closure")
    func getTip_randomRange() {
        let tip = StartupTipProvider.getTip(isFirstRun: false, randomRange: { _ in 0 })
        #expect(tip == StartupTipProvider.allTips[0])
    }

    // MARK: - Tip Content Quality

    @Test("allTips is non-empty")
    func allTips_nonEmpty() {
        #expect(!StartupTipProvider.allTips.isEmpty)
    }

    @Test("allTips has at least 5 tips for good variety")
    func allTips_minimumCount() {
        #expect(StartupTipProvider.allTips.count >= 5)
    }

    @Test("allTips are all non-empty and reasonably short")
    func allTips_quality() {
        for tip in StartupTipProvider.allTips {
            #expect(!tip.isEmpty)
            #expect(tip.count <= 100, "Tip too long: \(tip)")
        }
    }

    @Test("firstRunWelcome is non-empty")
    func firstRunWelcome_nonEmpty() {
        #expect(!StartupTipProvider.firstRunWelcome.isEmpty)
    }

    // MARK: - Rendering

    @Test("renderTip returns nil for empty string")
    func renderTip_empty() {
        let result = StartupTipProvider.renderTip("", isTTY: true, colorProfile: .unknown)
        #expect(result == nil)
    }

    @Test("renderTip plain text for non-TTY")
    func renderTip_nonTTY() {
        let result = StartupTipProvider.renderTip("Test tip", isTTY: false, colorProfile: .unknown)
        #expect(result == "💡 Test tip\n")
    }

    @Test("renderTip includes emoji prefix")
    func renderTip_emojiPrefix() {
        let result = StartupTipProvider.renderTip("Test tip", isTTY: false, colorProfile: .unknown)
        #expect(result != nil)
        #expect(result!.hasPrefix("💡"))
    }

    @Test("renderTip includes newline at end")
    func renderTip_newline() {
        let result = StartupTipProvider.renderTip("Test", isTTY: false, colorProfile: .unknown)
        #expect(result?.hasSuffix("\n") == true)
    }

    @Test("renderTip TTY trueColor includes ANSI escape codes")
    func renderTip_ttyTrueColor() {
        let result = StartupTipProvider.renderTip(
            "Test tip",
            isTTY: true,
            colorProfile: .trueColor
        )
        #expect(result != nil)
        // Should contain ANSI escape sequence (dim color) and reset
        #expect(result!.contains("\u{1B}[38;2;"))
        #expect(result!.contains("\u{1B}[0m"))
    }

    @Test("renderTip TTY ANSI256 includes ANSI codes")
    func renderTip_ttyANSI256() {
        let result = StartupTipProvider.renderTip(
            "Test tip",
            isTTY: true,
            colorProfile: .ansi256
        )
        #expect(result != nil)
        #expect(result!.contains("\u{1B}[38;5;"))
        #expect(result!.contains("\u{1B}[0m"))
    }

    @Test("renderTip TTY ANSI16 uses dim attribute")
    func renderTip_ttyANSI16() {
        let result = StartupTipProvider.renderTip(
            "Test tip",
            isTTY: true,
            colorProfile: .ansi16
        )
        #expect(result != nil)
        #expect(result!.contains("\u{1B}[2m"))  // dim/faint
        #expect(result!.contains("\u{1B}[0m"))
    }

    @Test("renderTip unknown profile falls back to plain text")
    func renderTip_unknownProfile() {
        let result = StartupTipProvider.renderTip(
            "Test tip",
            isTTY: true,
            colorProfile: .unknown
        )
        #expect(result == "💡 Test tip\n")
    }

    // MARK: - Integration

    @Test("Full first-run flow: detection → tip → render")
    func integration_firstRun() {
        let isFirstRun = StartupTipProvider.isFirstRun(
            historyFilePath: "/nonexistent",
            fileExists: { _ in false }
        )
        #expect(isFirstRun == true)

        let tip = StartupTipProvider.getTip(isFirstRun: isFirstRun)
        #expect(tip == StartupTipProvider.firstRunWelcome)

        let rendered = StartupTipProvider.renderTip(tip, isTTY: false, colorProfile: .unknown)
        #expect(rendered != nil)
        #expect(rendered!.contains("欢迎"))
    }

    @Test("Full returning-user flow: detection → tip → render")
    func integration_returningUser() {
        let isFirstRun = StartupTipProvider.isFirstRun(
            historyFilePath: "/exists",
            fileExists: { _ in true }
        )
        #expect(isFirstRun == false)

        let tip = StartupTipProvider.getTip(isFirstRun: isFirstRun, tipIndex: 0)
        #expect(StartupTipProvider.allTips.contains(tip))

        let rendered = StartupTipProvider.renderTip(tip, isTTY: true, colorProfile: .trueColor)
        #expect(rendered != nil)
        #expect(rendered!.contains("💡"))
    }
}
