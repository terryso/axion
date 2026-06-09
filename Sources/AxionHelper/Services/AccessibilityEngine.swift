import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Errors thrown by `AccessibilityEngineService`.
enum AccessibilityEngineError: Error, LocalizedError, ToolErrorProtocol {
    case windowNotFound(windowId: Int)
    case axPermissionDenied
    case axTreeBuildFailed(reason: String)
    case appNotFound(pid: Int32)
    case activationFailed(pid: Int32)

    var errorDescription: String? {
        switch self {
        case .windowNotFound(let id):
            return "Window with id \(id) not found"
        case .axPermissionDenied:
            return "Accessibility permission not granted"
        case .axTreeBuildFailed(let reason):
            return "Failed to build AX tree: \(reason)"
        case .appNotFound(let pid):
            return "Application with pid \(pid) not found"
        case .activationFailed(let pid):
            return "Failed to activate application with pid \(pid)"
        }
    }

    var errorCode: String {
        switch self {
        case .windowNotFound:
            return "window_not_found"
        case .axPermissionDenied:
            return "ax_permission_denied"
        case .axTreeBuildFailed:
            return "ax_tree_build_failed"
        case .appNotFound:
            return "app_not_found"
        case .activationFailed:
            return "activation_failed"
        }
    }

    var suggestion: String {
        switch self {
        case .windowNotFound:
            return "Use list_windows to get valid window IDs."
        case .axPermissionDenied:
            return "Grant Accessibility permission in System Settings > Privacy & Security."
        case .axTreeBuildFailed:
            return "Ensure the target application is responsive."
        case .appNotFound:
            return "Use list_apps to get valid process IDs."
        case .activationFailed:
            return "Ensure the application is responsive and not minimized."
        }
    }
}

/// Service that interacts with macOS Accessibility APIs and CoreGraphics
/// to manage window information.
struct AccessibilityEngineService: WindowManaging {

    // MARK: - Public API

    func listWindows(pid: Int32? = nil) -> [WindowInfo] {
        let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []

        var appLookup: [Int32: (bundleId: String?, localizedName: String?)] = [:]
        for app in NSWorkspace.shared.runningApplications {
            appLookup[app.processIdentifier] = (app.bundleIdentifier, app.localizedName)
        }

        return windowList.enumerated().compactMap { (index, info) -> WindowInfo? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32 else { return nil }
            if let pid, ownerPID != pid { return nil }
            guard let windowID = info[kCGWindowNumber as String] as? Int else { return nil }

            let title = info[kCGWindowName as String] as? String
            let cgAppName = info[kCGWindowOwnerName as String] as? String
            let appInfo = appLookup[ownerPID]
            let bundleId = appInfo?.bundleId

            var appName = cgAppName ?? appInfo?.localizedName
            if let bundleId, let canonicalName = extractAppName(from: bundleId) {
                if let current = appName, !current.lowercased().contains(canonicalName.lowercased()) {
                    appName = "\(current) (\(canonicalName))"
                }
            }

            let bounds = parseCGBounds(info["kCGWindowBounds"] as? [String: Any])

            if bounds.width == 0, bounds.height == 0 { return nil }

            return WindowInfo(
                windowId: windowID,
                pid: ownerPID,
                title: title,
                appName: appName,
                bundleId: bundleId,
                bounds: bounds,
                zOrder: index
            )
        }
    }

    func getWindowState(windowId: Int) throws -> WindowState {
        guard let cgWindow = findCGWindow(windowId: windowId) else {
            throw AccessibilityEngineError.windowNotFound(windowId: windowId)
        }

        guard let ownerPID = cgWindow[kCGWindowOwnerPID as String] as? Int32 else {
            throw AccessibilityEngineError.windowNotFound(windowId: windowId)
        }

        let title = cgWindow[kCGWindowName as String] as? String
        let cgBounds = parseCGBounds(cgWindow["kCGWindowBounds"] as? [String: Any])

        let axState = getAXWindowState(pid: ownerPID, title: title, bounds: cgBounds)

        let isFocused = axState?.isFocused ?? false
        let isMinimized: Bool
        if let axMin = axState?.isMinimized {
            isMinimized = axMin
        } else {
            let isOnscreen = cgWindow[kCGWindowIsOnscreen as String] as? Bool ?? true
            isMinimized = !isOnscreen && cgBounds.width > 0 && cgBounds.height > 0
        }
        let axTree = axState?.axTree

        let appName = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == ownerPID })?.localizedName

        return WindowState(
            windowId: windowId,
            pid: ownerPID,
            title: title,
            bounds: cgBounds,
            isMinimized: isMinimized,
            isFocused: isFocused,
            axTree: axTree,
            appName: appName
        )
    }

    func setWindowBounds(windowId: Int, x: Int? = nil, y: Int? = nil, width: Int? = nil, height: Int? = nil) throws {
        guard let cgWindow = findCGWindow(windowId: windowId) else {
            throw AccessibilityEngineError.windowNotFound(windowId: windowId)
        }

        guard let ownerPID = cgWindow[kCGWindowOwnerPID as String] as? Int32 else {
            throw AccessibilityEngineError.windowNotFound(windowId: windowId)
        }

        let currentBounds = parseCGBounds(cgWindow["kCGWindowBounds"] as? [String: Any])
        let newX = x ?? currentBounds.x
        let newY = y ?? currentBounds.y
        let newWidth = width ?? currentBounds.width
        let newHeight = height ?? currentBounds.height

        let title = cgWindow[kCGWindowName as String] as? String
        guard let axWindows = fetchAXWindows(pid: ownerPID) else {
            throw AccessibilityEngineError.axTreeBuildFailed(reason: "No AX windows found for pid \(ownerPID)")
        }

        guard let matchedWindow = matchAXWindow(axWindows: axWindows, title: title) else {
            throw AccessibilityEngineError.axTreeBuildFailed(reason: "Cannot match AX window for window_id \(windowId)")
        }

        var position = CGPoint(x: CGFloat(newX), y: CGFloat(newY))
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(matchedWindow, kAXPositionAttribute as CFString, posValue)
        }

        var size = CGSize(width: CGFloat(newWidth), height: CGFloat(newHeight))
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(matchedWindow, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    func activateWindow(pid: Int32, windowId: Int? = nil) throws {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw AccessibilityEngineError.appNotFound(pid: pid)
        }

        let activated = app.activate()
        guard activated else {
            throw AccessibilityEngineError.activationFailed(pid: pid)
        }

        // If a specific window is requested, raise it via AX
        if let windowId {
            raiseAXWindow(pid: pid, windowId: windowId)
        }
    }

    func validateWindow(windowId: Int) -> ValidateWindowResult {
        guard let cgWindow = findCGWindow(windowId: windowId) else {
            return ValidateWindowResult(
                windowId: windowId,
                exists: false,
                actionable: false,
                title: nil,
                pid: nil,
                reason: "Window \(windowId) not found"
            )
        }

        let ownerPID = cgWindow[kCGWindowOwnerPID as String] as? Int32
        let title = cgWindow[kCGWindowName as String] as? String
        let isOnscreen = cgWindow[kCGWindowIsOnscreen as String] as? Bool ?? true
        let bounds = parseCGBounds(cgWindow["kCGWindowBounds"] as? [String: Any])

        let actionable = isOnscreen && bounds.width > 0 && bounds.height > 0

        var reason: String?
        if !actionable {
            if !isOnscreen {
                reason = "Window is offscreen or minimized"
            } else if bounds.width == 0 || bounds.height == 0 {
                reason = "Window has zero-size bounds"
            }
        }

        return ValidateWindowResult(
            windowId: windowId,
            exists: true,
            actionable: actionable,
            title: title,
            pid: ownerPID.map { Int($0) },
            reason: reason
        )
    }

    // MARK: - Internal Helpers

    /// Finds a CG window dictionary by window ID from the full window list.
    /// Returns the raw CG window info dict, or nil if not found.
    func findCGWindow(windowId: Int) -> [String: Any]? {
        let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        return windowList.first { $0[kCGWindowNumber as String] as? Int == windowId }
    }

    /// Fetches the list of AX windows for a given process ID.
    /// Returns nil if AX is unavailable or the process has no windows.
    func fetchAXWindows(pid: Int32) -> [AXUIElement]? {
        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)
        guard axResult == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
            return nil
        }
        return axWindows
    }

    func parseCGBounds(_ dict: [String: Any]?) -> WindowBounds {
        guard let dict else {
            return WindowBounds(x: 0, y: 0, width: 0, height: 0)
        }
        return WindowBounds(
            x: Int(dict["X"] as? CGFloat ?? dict["x"] as? CGFloat ?? 0),
            y: Int(dict["Y"] as? CGFloat ?? dict["y"] as? CGFloat ?? 0),
            width: Int(dict["Width"] as? CGFloat ?? dict["width"] as? CGFloat ?? 0),
            height: Int(dict["Height"] as? CGFloat ?? dict["height"] as? CGFloat ?? 0)
        )
    }

    func extractAppName(from bundleId: String) -> String? {
        let parts = bundleId.split(separator: ".")
        guard let last = parts.last, !last.isEmpty else { return nil }
        return String(last)
    }

    private struct AXWindowState {
        let isFocused: Bool
        let isMinimized: Bool?
        let axTree: AXElement?
    }

    private func getAXWindowState(pid: Int32, title: String?, bounds: WindowBounds) -> AXWindowState? {
        guard let axWindows = fetchAXWindows(pid: pid),
              let matchedWindow = matchAXWindow(axWindows: axWindows, title: title) else {
            return nil
        }

        var focusedRef: AnyObject?
        AXUIElementCopyAttributeValue(matchedWindow, kAXFocusedAttribute as CFString, &focusedRef)
        let isFocused = (focusedRef as? Bool) ?? false

        var minimizedRef: AnyObject?
        AXUIElementCopyAttributeValue(matchedWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
        let isMinimized = minimizedRef as? Bool

        let axTree = buildAXTree(element: matchedWindow, maxDepth: 8, maxNodes: 300)

        return AXWindowState(isFocused: isFocused, isMinimized: isMinimized, axTree: axTree)
    }
}
