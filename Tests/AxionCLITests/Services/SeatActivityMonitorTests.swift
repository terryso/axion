import Foundation
import Testing

@testable import AxionCLI

@Suite("SeatActivityMonitor Tests")
struct SeatActivityMonitorTests {

    // MARK: - describeBaseline

    @Test("describeBaseline returns both cursor and frontmost when both present")
    func test_describeBaseline_bothPresent() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 100, y: 200),
            baselineFrontmost: "com.apple.Safari"
        )
        let desc = await monitor.describeBaseline()
        #expect(desc == "cursor=(100,200) frontmost=com.apple.Safari")
    }

    @Test("describeBaseline returns only cursor when frontmost is nil")
    func test_describeBaseline_cursorOnly() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 50, y: 75),
            baselineFrontmost: nil
        )
        let desc = await monitor.describeBaseline()
        #expect(desc == "cursor=(50,75)")
    }

    @Test("describeBaseline returns only frontmost when cursor is nil")
    func test_describeBaseline_frontmostOnly() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: nil,
            baselineFrontmost: "com.apple.Terminal"
        )
        let desc = await monitor.describeBaseline()
        #expect(desc == "frontmost=com.apple.Terminal")
    }

    @Test("describeBaseline returns empty string when both nil")
    func test_describeBaseline_bothNil() async {
        let monitor = SeatActivityMonitor(baselineCursor: nil, baselineFrontmost: nil)
        let desc = await monitor.describeBaseline()
        #expect(desc == "")
    }

    // MARK: - check: cursor movement detection

    @Test("check detects cursor movement >= 8px")
    func test_check_cursorMoved() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 0, y: 0),
            baselineFrontmost: "com.apple.Safari"
        )
        let result = await monitor.checkState(
            currentCursor: CGPoint(x: 10, y: 0),
            currentFrontmost: "com.apple.Safari"
        )
        #expect(result != nil)
        #expect(result?.contains("cursor moved") == true)
        #expect(result?.contains("10px") == true)
    }

    @Test("check does not detect cursor movement < 8px")
    func test_check_cursorSmallMove() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 0, y: 0),
            baselineFrontmost: "com.apple.Safari"
        )
        let result = await monitor.checkState(
            currentCursor: CGPoint(x: 5, y: 5),
            currentFrontmost: "com.apple.Safari"
        )
        // hypot(5, 5) ≈ 7.07 < 8
        #expect(result == nil)
    }

    @Test("check detects cursor movement at exactly 8px boundary")
    func test_check_cursorExact8px() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 0, y: 0),
            baselineFrontmost: "com.apple.Safari"
        )
        let result = await monitor.checkState(
            currentCursor: CGPoint(x: 8, y: 0),
            currentFrontmost: "com.apple.Safari"
        )
        // Exactly 8px — should trigger
        #expect(result != nil)
        #expect(result?.contains("cursor moved") == true)
    }

    @Test("check does not detect when cursor exactly at baseline")
    func test_check_cursorNoMove() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 100, y: 200),
            baselineFrontmost: "com.apple.Safari"
        )
        let result = await monitor.checkState(
            currentCursor: CGPoint(x: 100, y: 200),
            currentFrontmost: "com.apple.Safari"
        )
        #expect(result == nil)
    }

    // MARK: - check: frontmost app change detection

    @Test("check detects frontmost app change")
    func test_check_frontmostChanged() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 100, y: 200),
            baselineFrontmost: "com.apple.Safari"
        )
        let result = await monitor.checkState(
            currentCursor: CGPoint(x: 100, y: 200),
            currentFrontmost: "com.apple.TextEdit"
        )
        #expect(result != nil)
        #expect(result?.contains("frontmost app changed") == true)
        #expect(result?.contains("com.apple.Safari") == true)
        #expect(result?.contains("com.apple.TextEdit") == true)
    }

    // MARK: - check: no change returns nil

    @Test("check returns nil when no changes")
    func test_check_noChanges() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 100, y: 200),
            baselineFrontmost: "com.apple.Safari"
        )
        let result = await monitor.checkState(
            currentCursor: CGPoint(x: 100, y: 200),
            currentFrontmost: "com.apple.Safari"
        )
        #expect(result == nil)
    }

    // MARK: - reported Set dedup

    @Test("same change type reported only once")
    func test_check_dedupCursor() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 0, y: 0),
            baselineFrontmost: "com.apple.Safari"
        )
        // First check — should detect
        let r1 = await monitor.checkState(
            currentCursor: CGPoint(x: 20, y: 0),
            currentFrontmost: "com.apple.Safari"
        )
        #expect(r1 != nil)

        // Second check — same change type, should be deduped
        let r2 = await monitor.checkState(
            currentCursor: CGPoint(x: 30, y: 0),
            currentFrontmost: "com.apple.Safari"
        )
        #expect(r2 == nil)
    }

    @Test("different change types each reported once")
    func test_check_dedupDifferentTypes() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 0, y: 0),
            baselineFrontmost: "com.apple.Safari"
        )
        // First: cursor change
        let r1 = await monitor.checkState(
            currentCursor: CGPoint(x: 20, y: 0),
            currentFrontmost: "com.apple.Safari"
        )
        #expect(r1?.contains("cursor moved") == true)

        // Second: frontmost change (cursor already reported)
        let r2 = await monitor.checkState(
            currentCursor: CGPoint(x: 30, y: 0),
            currentFrontmost: "com.apple.TextEdit"
        )
        #expect(r2?.contains("frontmost app changed") == true)

        // Third: both already reported
        let r3 = await monitor.checkState(
            currentCursor: CGPoint(x: 50, y: 0),
            currentFrontmost: "com.apple.Mail"
        )
        #expect(r3 == nil)
    }

    // MARK: - externallyModified flag

    @Test("externallyModified is false initially")
    func test_externallyModified_initialFalse() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 0, y: 0),
            baselineFrontmost: "com.apple.Safari"
        )
        let modified = await monitor.externallyModified
        #expect(modified == false)
    }

    @Test("externallyModified set to true on first detection")
    func test_externallyModified_setTrue() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 0, y: 0),
            baselineFrontmost: "com.apple.Safari"
        )
        _ = await monitor.checkState(
            currentCursor: CGPoint(x: 20, y: 0),
            currentFrontmost: "com.apple.Safari"
        )
        let modified = await monitor.externallyModified
        #expect(modified == true)
    }

    @Test("externallyModified stays false when no activity")
    func test_externallyModified_staysFalse() async {
        let monitor = SeatActivityMonitor(
            baselineCursor: CGPoint(x: 100, y: 200),
            baselineFrontmost: "com.apple.Safari"
        )
        _ = await monitor.checkState(
            currentCursor: CGPoint(x: 100, y: 200),
            currentFrontmost: "com.apple.Safari"
        )
        let modified = await monitor.externallyModified
        #expect(modified == false)
    }

    // MARK: - create() baseline sampling

    @Test("create() returns non-nil monitor with sampled baseline")
    func test_create_returnsNonNil() async {
        let monitor = await SeatActivityMonitor.create()
        #expect(monitor != nil)
        if let monitor {
            let desc = await monitor.describeBaseline()
            // Should contain cursor info at minimum (NSEvent.mouseLocation always returns a value)
            #expect(desc.contains("cursor="))
        }
    }
}
