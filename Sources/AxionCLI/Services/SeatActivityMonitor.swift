import AppKit
import Foundation

/// Monitors desktop activity during shared-seat runs to detect external user intervention.
///
/// When the user manually operates the desktop (mouse movement or frontmost app change)
/// during an automated run, the run is marked as "externally modified" so that memory
/// extraction is skipped — preventing the run's corrupted state from polluting learning.
///
/// Uses actor isolation for thread-safe state management (matching RunLockService,
/// VisualDeltaTracker patterns).
actor SeatActivityMonitor {

    // MARK: - Properties

    private let baselineCursor: CGPoint?
    private let baselineFrontmost: String?
    private var reported: Set<String> = []
    private(set) var externallyModified: Bool = false

    // MARK: - Initialization

    init(baselineCursor: CGPoint?, baselineFrontmost: String?) {
        self.baselineCursor = baselineCursor
        self.baselineFrontmost = baselineFrontmost
    }

    /// Samples the current desktop state and creates a monitor if possible.
    static func create() -> SeatActivityMonitor? {
        let cursor = NSEvent.mouseLocation
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return SeatActivityMonitor(baselineCursor: cursor, baselineFrontmost: frontmost)
    }

    // MARK: - Baseline Description

    /// Returns a human-readable description of the baseline state for trace recording.
    func describeBaseline() -> String {
        var parts: [String] = []
        if let cursor = baselineCursor {
            parts.append("cursor=(\(Int(cursor.x)),\(Int(cursor.y)))")
        }
        if let frontmost = baselineFrontmost {
            parts.append("frontmost=\(frontmost)")
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Activity Check

    /// Samples current cursor position and frontmost app, compares against baseline.
    /// Returns a description of detected changes, or nil if no significant activity detected.
    /// Each change type is reported only once (deduplication via `reported` Set).
    func check() -> String? {
        let currentCursor = NSEvent.mouseLocation
        let currentFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return checkState(currentCursor: currentCursor, currentFrontmost: currentFrontmost)
    }

    /// Internal comparison logic — separated for testability without AppKit dependencies.
    func checkState(currentCursor: CGPoint, currentFrontmost: String?) -> String? {
        var changes: [String] = []

        if let baseline = baselineCursor {
            let distance = hypot(currentCursor.x - baseline.x, currentCursor.y - baseline.y)
            if distance >= 8 && !reported.contains("cursor") {
                reported.insert("cursor")
                changes.append("cursor moved \(Int(round(distance)))px from baseline (\(Int(baseline.x)),\(Int(baseline.y)))")
            }
        }

        if let baseline = baselineFrontmost, let current = currentFrontmost,
           current != baseline && !reported.contains("frontmost") {
            reported.insert("frontmost")
            changes.append("frontmost app changed from \(baseline) to \(current)")
        }

        if !changes.isEmpty {
            externallyModified = true
            return changes.joined(separator: "; ")
        }
        return nil
    }
}
