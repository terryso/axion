import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Errors thrown by `AccessibilityEngineService`.
enum AccessibilityEngineError: Error, LocalizedError {
    case windowNotFound(windowId: Int)
    case axPermissionDenied
    case axTreeBuildFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .windowNotFound(let id):
            return "Window with id \(id) not found"
        case .axPermissionDenied:
            return "Accessibility permission not granted"
        case .axTreeBuildFailed(let reason):
            return "Failed to build AX tree: \(reason)"
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

        return windowList.compactMap { info -> WindowInfo? in
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
                bounds: bounds
            )
        }
    }

    func getWindowState(windowId: Int) throws -> WindowState {
        let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []

        guard let cgWindow = windowList.first(where: {
            $0[kCGWindowNumber as String] as? Int == windowId
        }) else {
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

        return WindowState(
            windowId: windowId,
            pid: ownerPID,
            title: title,
            bounds: cgBounds,
            isMinimized: isMinimized,
            isFocused: isFocused,
            axTree: axTree
        )
    }

    // MARK: - Private Helpers

    private func parseCGBounds(_ dict: [String: Any]?) -> WindowBounds {
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

    private struct AXWindowState {
        let isFocused: Bool
        let isMinimized: Bool?
        let axTree: AXElement?
    }

    private func getAXWindowState(pid: Int32, title: String?, bounds: WindowBounds) -> AXWindowState? {
        let axApp = AXUIElementCreateApplication(pid)

        var windowsRef: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

        guard axResult == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
            return nil
        }

        var matchedWindow: AXUIElement?

        for axWindow in axWindows {
            var axTitleRef: AnyObject?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &axTitleRef)
            let axTitle = axTitleRef as? String

            if let title, let axTitle, axTitle == title {
                matchedWindow = axWindow
                break
            }
        }

        if matchedWindow == nil {
            for axWindow in axWindows {
                var axTitleRef: AnyObject?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &axTitleRef)
                let axTitle = axTitleRef as? String

                if let title, let axTitle,
                   axTitle.lowercased().contains(title.lowercased()) || title.lowercased().contains(axTitle.lowercased()) {
                    matchedWindow = axWindow
                    break
                }
            }
        }

        if matchedWindow == nil, let first = axWindows.first {
            matchedWindow = first
        }

        guard let matchedWindow else {
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

    func buildAXTree(element: AXUIElement, maxDepth: Int = 8, maxNodes: Int = 300) -> AXElement {
        let budget = NodeBudget(maxNodes)
        return buildAXTreeInternal(element: element, depth: maxDepth, budget: budget)
    }

    private class NodeBudget {
        var remaining: Int
        init(_ count: Int) { remaining = count }
    }

    private func buildAXTreeInternal(element: AXUIElement, depth: Int, budget: NodeBudget) -> AXElement {
        var role: String = ""
        var ref: AnyObject?

        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &ref)
        role = (ref as? String) ?? "Unknown"

        ref = nil
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref)
        let title = ref as? String

        ref = nil
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &ref)
        let value: String?
        if let stringValue = ref as? String {
            value = stringValue
        } else {
            value = nil
        }

        ref = nil
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref)
        var position = CGPoint.zero
        if let axVal = ref, CFGetTypeID(axVal) == AXValueGetTypeID() {
            var cgPoint = CGPoint.zero
            if AXValueGetValue(axVal as! AXValue, .cgPoint, &cgPoint) {
                position = cgPoint
            }
        }

        ref = nil
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref)
        var size = CGSize.zero
        if let axVal = ref, CFGetTypeID(axVal) == AXValueGetTypeID() {
            var cgSize = CGSize.zero
            if AXValueGetValue(axVal as! AXValue, .cgSize, &cgSize) {
                size = cgSize
            }
        }

        let bounds = WindowBounds(
            x: Int(position.x),
            y: Int(position.y),
            width: Int(size.width),
            height: Int(size.height)
        )

        var children: [AXElement] = []
        if depth > 0, budget.remaining > 0 {
            ref = nil
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref)
            if let axChildren = ref as? [AXUIElement] {
                for child in axChildren {
                    guard budget.remaining > 0 else { break }
                    budget.remaining -= 1
                    children.append(buildAXTreeInternal(
                        element: child,
                        depth: depth - 1,
                        budget: budget
                    ))
                }
            }
        }

        return AXElement(role: role, title: title, value: value, bounds: bounds, children: children)
    }

    private func extractAppName(from bundleId: String) -> String? {
        let parts = bundleId.split(separator: ".")
        guard let last = parts.last, !last.isEmpty else { return nil }
        return String(last)
    }
}
