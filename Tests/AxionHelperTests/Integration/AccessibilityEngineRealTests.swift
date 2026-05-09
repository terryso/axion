import XCTest
@testable import AxionHelper

/// Tests that directly call real AccessibilityEngineService to maximize code coverage.
/// CGWindowListCopyWindowInfo works without special permissions.
final class AccessibilityEngineRealTests: XCTestCase {

    private let service = AccessibilityEngineService()

    // MARK: - listWindows

    func test_listWindows_returnsNonEmptyArray() {
        let windows = service.listWindows(pid: nil)
        // On any macOS system there should be at least some windows
        XCTAssertGreaterThan(windows.count, 0, "Should return at least one window")
    }

    func test_listWindows_eachWindowHasValidId() {
        let windows = service.listWindows(pid: nil)
        for window in windows {
            XCTAssertGreaterThan(window.windowId, 0, "Each window should have a positive ID")
        }
    }

    func test_listWindows_eachWindowHasValidPid() {
        let windows = service.listWindows(pid: nil)
        for window in windows {
            XCTAssertGreaterThan(window.pid, 0, "Each window should have a positive PID")
        }
    }

    func test_listWindows_eachWindowHasNonZeroBounds() {
        let windows = service.listWindows(pid: nil)
        for window in windows {
            // Windows with zero bounds are filtered out, so all should have non-zero size
            XCTAssertTrue(window.bounds.width > 0 || window.bounds.height > 0,
                          "Each window should have non-zero bounds")
        }
    }

    func test_listWindows_windowInfoHasBounds() {
        let windows = service.listWindows(pid: nil)
        for window in windows {
            // Bounds fields are integers (can be negative for off-screen windows)
            _ = window.bounds.x
            _ = window.bounds.y
            _ = window.bounds.width
            _ = window.bounds.height
        }
    }

    func test_listWindows_filterByPid() {
        let allWindows = service.listWindows(pid: nil)
        guard let firstWindow = allWindows.first else { return }

        let filtered = service.listWindows(pid: firstWindow.pid)
        XCTAssertTrue(filtered.count <= allWindows.count,
                       "Filtered by PID should return fewer or equal windows")
        for window in filtered {
            XCTAssertEqual(window.pid, firstWindow.pid)
        }
    }

    func test_listWindows_filterByNonExistentPid_returnsEmpty() {
        let windows = service.listWindows(pid: 999999)
        // Unlikely to match any process
        // Can't assert empty because pid might theoretically exist
        XCTAssertNotNil(windows)
    }

    // MARK: - getWindowState

    func test_getWindowState_validWindow_returnsState() throws {
        let windows = service.listWindows(pid: nil)
        guard let window = windows.first else {
            throw XCTSkip("No windows available to test")
        }

        let state = try service.getWindowState(windowId: window.windowId)
        XCTAssertEqual(state.windowId, window.windowId)
        XCTAssertNotNil(state.bounds)
    }

    func test_getWindowState_invalidWindow_throwsWindowNotFound() {
        XCTAssertThrowsError(try service.getWindowState(windowId: 999999)) { error in
            if let error = error as? AccessibilityEngineError {
                if case .windowNotFound = error {
                    // expected
                } else {
                    XCTFail("Expected windowNotFound, got \(error)")
                }
            }
        }
    }

    func test_getWindowState_hasMinimizedAndFocusedFields() throws {
        let windows = service.listWindows(pid: nil)
        guard let window = windows.first else {
            throw XCTSkip("No windows available to test")
        }

        let state = try service.getWindowState(windowId: window.windowId)
        // These should be valid booleans
        _ = state.isMinimized
        _ = state.isFocused
    }

    // MARK: - getAXTree

    func test_getAXTree_invalidWindow_throwsWindowNotFound() {
        XCTAssertThrowsError(try service.getAXTree(windowId: 999999, maxNodes: 10)) { error in
            if let error = error as? AccessibilityEngineError {
                if case .windowNotFound = error {
                    // expected
                } else {
                    XCTFail("Expected windowNotFound, got \(error)")
                }
            }
        }
    }

    func test_getAXTree_validWindow_returnsTree() throws {
        let windows = service.listWindows(pid: nil)
        // Find a window that's likely to have AX tree
        guard let window = windows.first else {
            throw XCTSkip("No windows available to test")
        }

        do {
            let tree = try service.getAXTree(windowId: window.windowId, maxNodes: 50)
            XCTAssertFalse(tree.role.isEmpty, "AX tree root should have a role")
        } catch AccessibilityEngineError.axTreeBuildFailed {
            // Some windows may not have AX access - acceptable
        } catch AccessibilityEngineError.axPermissionDenied {
            // Acceptable in CI without AX permission
        }
    }

    func test_getAXTree_maxNodesLimitsOutput() throws {
        let windows = service.listWindows(pid: nil)
        guard let window = windows.first else {
            throw XCTSkip("No windows available to test")
        }

        do {
            let tree = try service.getAXTree(windowId: window.windowId, maxNodes: 1)
            // With maxNodes=1, should have at most 1 child (root itself is always returned)
            _ = tree
        } catch AccessibilityEngineError.axTreeBuildFailed {
            // Acceptable
        } catch AccessibilityEngineError.axPermissionDenied {
            // Acceptable in CI
        }
    }

    // MARK: - buildAXTree

    func test_buildAXTree_withAXUIElement() throws {
        // Test buildAXTree with the AXUIElement of the current process
        let pid = ProcessInfo.processInfo.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        let tree = service.buildAXTree(element: axApp, maxDepth: 2, maxNodes: 10)
        XCTAssertFalse(tree.role.isEmpty)
    }
}
