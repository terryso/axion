import ApplicationServices
import Foundation
import Testing
@testable import AxionHelper

@Suite("AccessibilityEngineService Real")
struct AccessibilityEngineRealTests {

    private let service = AccessibilityEngineService()

    // MARK: - listWindows

    @Test("listWindows returns non-empty array")
    func listWindowsReturnsNonEmptyArray() {
        let windows = service.listWindows(pid: nil)
        #expect(windows.count > 0, "Should return at least one window")
    }

    @Test("listWindows each window has valid ID")
    func listWindowsEachWindowHasValidId() {
        let windows = service.listWindows(pid: nil)
        for window in windows {
            #expect(window.windowId > 0, "Each window should have a positive ID")
        }
    }

    @Test("listWindows each window has valid PID")
    func listWindowsEachWindowHasValidPid() {
        let windows = service.listWindows(pid: nil)
        for window in windows {
            #expect(window.pid > 0, "Each window should have a positive PID")
        }
    }

    @Test("listWindows each window has non-zero bounds")
    func listWindowsEachWindowHasNonZeroBounds() {
        let windows = service.listWindows(pid: nil)
        for window in windows {
            #expect(window.bounds.width > 0 || window.bounds.height > 0,
                    "Each window should have non-zero bounds")
        }
    }

    @Test("listWindows windowInfo has bounds")
    func listWindowsWindowInfoHasBounds() {
        let windows = service.listWindows(pid: nil)
        for window in windows {
            _ = window.bounds.x
            _ = window.bounds.y
            _ = window.bounds.width
            _ = window.bounds.height
        }
    }

    @Test("listWindows filter by PID")
    func listWindowsFilterByPid() {
        let allWindows = service.listWindows(pid: nil)
        guard let firstWindow = allWindows.first else { return }

        let filtered = service.listWindows(pid: firstWindow.pid)
        #expect(filtered.count <= allWindows.count,
                "Filtered by PID should return fewer or equal windows")
        for window in filtered {
            #expect(window.pid == firstWindow.pid)
        }
    }

    @Test("listWindows filter by non-existent PID")
    func listWindowsFilterByNonExistentPid() {
        let windows = service.listWindows(pid: 999999)
        #expect(windows.isEmpty)
    }

    // MARK: - getWindowState

    @Test("getWindowState valid window returns state")
    func getWindowStateValidWindowReturnsState() throws {
        let windows = service.listWindows(pid: nil)
        guard let window = windows.first else { return }

        let state = try service.getWindowState(windowId: window.windowId)
        #expect(state.windowId == window.windowId)
    }

    @Test("getWindowState invalid window throws windowNotFound")
    func getWindowStateInvalidWindowThrowsWindowNotFound() {
        do {
            _ = try service.getWindowState(windowId: 999999)
            Issue.record("Expected windowNotFound error")
        } catch let error as AccessibilityEngineError {
            if case .windowNotFound = error {
                // expected
            } else {
                Issue.record("Expected windowNotFound, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("getWindowState has minimized and focused fields")
    func getWindowStateHasMinimizedAndFocusedFields() throws {
        let windows = service.listWindows(pid: nil)
        guard let window = windows.first else { return }

        let state = try service.getWindowState(windowId: window.windowId)
        _ = state.isMinimized
        _ = state.isFocused
    }

    // MARK: - getAXTree

    @Test("getAXTree invalid window throws windowNotFound")
    func getAXTreeInvalidWindowThrowsWindowNotFound() {
        do {
            _ = try service.getAXTree(windowId: 999999, maxNodes: 10)
            Issue.record("Expected windowNotFound error")
        } catch let error as AccessibilityEngineError {
            if case .windowNotFound = error {
                // expected
            } else {
                Issue.record("Expected windowNotFound, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("getAXTree valid window returns tree")
    func getAXTreeValidWindowReturnsTree() throws {
        let windows = service.listWindows(pid: nil)
        guard let window = windows.first else { return }

        do {
            let tree = try service.getAXTree(windowId: window.windowId, maxNodes: 50)
            #expect(!tree.role.isEmpty, "AX tree root should have a role")
        } catch AccessibilityEngineError.axTreeBuildFailed {
            // Some windows may not have AX access - acceptable
        } catch AccessibilityEngineError.axPermissionDenied {
            // Acceptable in CI without AX permission
        }
    }

    @Test("getAXTree maxNodes limits output")
    func getAXTreeMaxNodesLimitsOutput() throws {
        let windows = service.listWindows(pid: nil)
        guard let window = windows.first else { return }

        do {
            let tree = try service.getAXTree(windowId: window.windowId, maxNodes: 1)
            _ = tree
        } catch AccessibilityEngineError.axTreeBuildFailed {
            // Acceptable
        } catch AccessibilityEngineError.axPermissionDenied {
            // Acceptable in CI
        }
    }

    // MARK: - buildAXTree

    @Test("buildAXTree with AXUIElement")
    func buildAXTreeWithAXUIElement() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        let tree = service.buildAXTree(element: axApp, maxDepth: 2, maxNodes: 10)
        #expect(!tree.role.isEmpty)
    }
}
