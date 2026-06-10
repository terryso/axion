import Foundation
import Testing

@testable import AxionCLI

// MARK: - ToolUsageTracker Tests

@Suite("ToolUsageTracker Tests")
struct ToolUsageTrackerTests {

    // MARK: - Recording

    @Test("record increments count for tool name")
    func test_record_incrementsCount() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Edit")

        #expect(tracker.counts["Bash"] == 2)
        #expect(tracker.counts["Edit"] == 1)
        #expect(tracker.totalCount == 3)
        #expect(tracker.uniqueToolCount == 2)
    }

    @Test("totalCount is zero for empty tracker")
    func test_totalCount_emptyTracker() {
        let tracker = ToolUsageTracker()
        #expect(tracker.totalCount == 0)
        #expect(tracker.uniqueToolCount == 0)
        #expect(tracker.counts.isEmpty)
    }

    // MARK: - topTools

    @Test("topTools returns tools sorted by count descending")
    func test_topTools_sortedDescending() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Read")     // 1
        tracker.record(toolName: "Bash")     // 2
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Edit")     // 3
        tracker.record(toolName: "Edit")
        tracker.record(toolName: "Edit")

        let top = tracker.topTools(limit: 5)
        #expect(top.count == 3)
        #expect(top[0] == ToolUsageTracker.ToolRecord(toolName: "Edit", count: 3))
        #expect(top[1] == ToolUsageTracker.ToolRecord(toolName: "Bash", count: 2))
        #expect(top[2] == ToolUsageTracker.ToolRecord(toolName: "Read", count: 1))
    }

    @Test("topTools respects limit parameter")
    func test_topTools_respectsLimit() {
        var tracker = ToolUsageTracker()
        for i in 0..<10 {
            tracker.record(toolName: "Tool\(i)")
        }

        let top = tracker.topTools(limit: 3)
        #expect(top.count == 3)
    }

    @Test("topTools returns empty for empty tracker")
    func test_topTools_emptyTracker() {
        let tracker = ToolUsageTracker()
        #expect(tracker.topTools().isEmpty)
    }

    // MARK: - reset

    @Test("reset clears all records")
    func test_reset_clearsRecords() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Edit")
        #expect(tracker.totalCount == 2)

        tracker.reset()
        #expect(tracker.totalCount == 0)
        #expect(tracker.uniqueToolCount == 0)
        #expect(tracker.counts.isEmpty)
    }

    // MARK: - renderCompact

    @Test("renderCompact non-TTY format")
    func test_renderCompact_nonTTY() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Edit")

        let result = tracker.renderCompact(isTTY: false, profile: .unknown)
        #expect(result == "[tools: 3 calls (Bash 2, Edit 1)]")
    }

    @Test("renderCompact non-TTY zero tools")
    func test_renderCompact_nonTTY_zeroTools() {
        let tracker = ToolUsageTracker()
        let result = tracker.renderCompact(isTTY: false, profile: .unknown)
        #expect(result == "[tools: 0]")
    }

    @Test("renderCompact TTY includes ANSI codes")
    func test_renderCompact_tty_hasANSI() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Edit")

        let result = tracker.renderCompact(isTTY: true, profile: .trueColor)
        #expect(result.contains("\u{1B}["))
        #expect(result.contains("🔧"))
        #expect(result.contains("Bash"))
        #expect(result.contains("Edit"))
    }

    @Test("renderCompact TTY zero tools")
    func test_renderCompact_tty_zeroTools() {
        let tracker = ToolUsageTracker()
        let result = tracker.renderCompact(isTTY: true, profile: .trueColor)
        #expect(result == "🔧 0 tools")
    }

    // MARK: - renderDetailed

    @Test("renderDetailed returns nil for empty tracker")
    func test_renderDetailed_emptyTracker() {
        let tracker = ToolUsageTracker()
        #expect(tracker.renderDetailed(isTTY: false, profile: .unknown) == nil)
    }

    @Test("renderDetailed non-TTY format")
    func test_renderDetailed_nonTTY() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Edit")

        let result = tracker.renderDetailed(isTTY: false, profile: .unknown)
        #expect(result != nil)
        #expect(result!.contains("[tools: 3 calls]"))
        #expect(result!.contains("Bash"))
        #expect(result!.contains("Edit"))
    }

    @Test("renderDetailed TTY format includes header and bars")
    func test_renderDetailed_tty() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Edit")

        let result = tracker.renderDetailed(isTTY: true, profile: .trueColor)
        #expect(result != nil)
        #expect(result!.contains("🔧 工具使用"))
        #expect(result!.contains("█"))
        #expect(result!.contains("Bash"))
        #expect(result!.contains("Edit"))
    }

    @Test("renderDetailed TTY bars scale proportionally")
    func test_renderDetailed_tty_barScaling() {
        var tracker = ToolUsageTracker()
        // Bash: 10 calls → full bar
        for _ in 0..<10 { tracker.record(toolName: "Bash") }
        // Edit: 5 calls → half bar
        for _ in 0..<5 { tracker.record(toolName: "Edit") }

        let result = tracker.renderDetailed(maxBarWidth: 16, isTTY: true, profile: .trueColor)
        #expect(result != nil)

        // Bash line should have 16 █ chars (full bar)
        let bashLine = result!.components(separatedBy: "\n").first { $0.contains("Bash") }
        #expect(bashLine != nil)
        let bashBarCount = bashLine!.filter { $0 == "█" }.count
        #expect(bashBarCount == 16)

        // Edit line should have 8 █ chars (half bar)
        let editLine = result!.components(separatedBy: "\n").first { $0.contains("Edit") }
        #expect(editLine != nil)
        let editBarCount = editLine!.filter { $0 == "█" }.count
        #expect(editBarCount == 8)
    }

    @Test("renderDetailed TTY all color profiles")
    func test_renderDetailed_allProfiles() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Bash")

        for profile: TerminalColorProfile in [.trueColor, .ansi256, .ansi16] {
            let result = tracker.renderDetailed(isTTY: true, profile: profile)
            #expect(result != nil, "renderDetailed should return non-nil for \(profile)")
            #expect(result!.contains("Bash"))
        }
    }

    // MARK: - ToolRecord equality

    @Test("ToolRecord equality works correctly")
    func test_toolRecord_equality() {
        let a = ToolUsageTracker.ToolRecord(toolName: "Bash", count: 3)
        let b = ToolUsageTracker.ToolRecord(toolName: "Bash", count: 3)
        let c = ToolUsageTracker.ToolRecord(toolName: "Edit", count: 3)
        let d = ToolUsageTracker.ToolRecord(toolName: "Bash", count: 1)

        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }

    // MARK: - Integration with many tools

    @Test("handles many different tool names")
    func test_manyToolNames() {
        var tracker = ToolUsageTracker()
        let toolNames = ["Bash", "Edit", "Write", "Read", "Grep", "Glob", "Memory", "Skill", "WebSearch"]
        for name in toolNames {
            for _ in 0..<3 { tracker.record(toolName: name) }
        }

        #expect(tracker.totalCount == 27)
        #expect(tracker.uniqueToolCount == 9)

        let top = tracker.topTools(limit: 5)
        #expect(top.count == 5)
        // All should have count 3 since all have same frequency
        for record in top {
            #expect(record.count == 3)
        }
    }

    // MARK: - renderCompact with single tool

    @Test("renderCompact singular tool label")
    func test_renderCompact_singularTool() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Bash")

        // Non-TTY always uses plural "calls"
        let nonTTY = tracker.renderCompact(isTTY: false, profile: .unknown)
        #expect(nonTTY == "[tools: 1 calls (Bash 1)]")

        // TTY uses singular "1 tool"
        let tty = tracker.renderCompact(isTTY: true, profile: .trueColor)
        #expect(tty.contains("1 tool"))
        #expect(tty.contains("Bash"))
    }

    // MARK: - ANSI stripping helper

    @Test("renderDetailed TTY output can be stripped of ANSI codes")
    func test_renderDetailed_ansiStripping() {
        var tracker = ToolUsageTracker()
        tracker.record(toolName: "Bash")
        tracker.record(toolName: "Edit")

        let result = tracker.renderDetailed(isTTY: true, profile: .trueColor)!
        let stripped = result.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m",
            with: "",
            options: .regularExpression
        )
        // Stripped output should contain plain text content
        #expect(stripped.contains("Bash"))
        #expect(stripped.contains("Edit"))
        #expect(stripped.contains("█"))
        // Should not contain any escape sequences
        #expect(!stripped.contains("\u{1B}["))
    }
}
