import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Errors thrown by `AccessibilityEngineService`.
enum AccessibilityEngineError: Error, LocalizedError {
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
        let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []

        guard let cgWindow = windowList.first(where: {
            $0[kCGWindowNumber as String] as? Int == windowId
        }) else {
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

        let axApp = AXUIElementCreateApplication(ownerPID)
        let title = cgWindow[kCGWindowName as String] as? String
        var windowsRef: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

        guard axResult == .success, let axWindows = windowsRef as? [AXUIElement] else {
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

    struct SelectorMatchResult: Codable {
        let x: Int
        let y: Int
        let role: String
        let title: String?
    }

    enum SelectorError: Error, LocalizedError {
        case noMatch(query: SelectorQuery)
        case ordinalOutOfRange(ordinal: Int, matchCount: Int)

        var errorDescription: String? {
            switch self {
            case .noMatch(let query):
                return "No AX element matches selector: role=\(query.role ?? "*"), title=\(query.title ?? "*"), title_contains=\(query.titleContains ?? "*"), ax_id=\(query.axId ?? "*")"
            case .ordinalOutOfRange(let ordinal, let count):
                return "Ordinal \(ordinal) out of range (found \(count) matching elements)"
            }
        }

        var errorCode: String {
            switch self {
            case .noMatch: return "selector_no_match"
            case .ordinalOutOfRange: return "selector_ordinal_out_of_range"
            }
        }

        var suggestion: String {
            switch self {
            case .noMatch:
                return "Use get_accessibility_tree to inspect the current AX tree and find the correct selector values."
            case .ordinalOutOfRange:
                return "Use a lower ordinal value or inspect the AX tree to count matching elements."
            }
        }
    }

    func resolveSelector(windowId: Int, query: SelectorQuery) throws -> SelectorMatchResult {
        let ordinal = query.ordinal ?? 0
        guard ordinal >= 0 else {
            throw SelectorError.ordinalOutOfRange(ordinal: ordinal, matchCount: 0)
        }

        let tree = try getAXTree(windowId: windowId, maxNodes: 500)
        let matches = collectMatches(element: tree, query: query)

        guard !matches.isEmpty else {
            throw SelectorError.noMatch(query: query)
        }

        guard ordinal < matches.count else {
            throw SelectorError.ordinalOutOfRange(ordinal: ordinal, matchCount: matches.count)
        }

        let match = matches[ordinal]
        return match
    }

    func collectMatches(element: AXElement, query: SelectorQuery) -> [SelectorMatchResult] {
        var results: [SelectorMatchResult] = []

        if matchesQuery(element: element, query: query),
           let bounds = element.bounds, bounds.width > 0, bounds.height > 0 {
            let centerX = bounds.x + bounds.width / 2
            let centerY = bounds.y + bounds.height / 2
            results.append(SelectorMatchResult(
                x: centerX,
                y: centerY,
                role: element.role,
                title: element.title
            ))
        }

        for child in element.children {
            results.append(contentsOf: collectMatches(element: child, query: query))
        }

        return results
    }

    private func matchesQuery(element: AXElement, query: SelectorQuery) -> Bool {
        guard query.title != nil || query.titleContains != nil || query.axId != nil || query.role != nil else {
            return false
        }
        if let role = query.role, element.role != role { return false }
        if let title = query.title, element.title != title { return false }
        if let titleContains = query.titleContains {
            guard let elementTitle = element.title,
                  elementTitle.localizedCaseInsensitiveContains(titleContains) else { return false }
        }
        if let axId = query.axId, element.identifier != axId { return false }
        return true
    }

    func validateWindow(windowId: Int) -> ValidateWindowResult {
        let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []

        guard let cgWindow = windowList.first(where: {
            $0[kCGWindowNumber as String] as? Int == windowId
        }) else {
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

    // MARK: - Private Helpers

    func getAXTree(windowId: Int, maxNodes: Int = 500) throws -> AXElement {
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

        let axApp = AXUIElementCreateApplication(ownerPID)

        var windowsRef: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

        guard axResult == .success, let axWindows = windowsRef as? [AXUIElement], !axWindows.isEmpty else {
            throw AccessibilityEngineError.axTreeBuildFailed(reason: "No AX windows found for pid \(ownerPID)")
        }

        let matchedWindow = matchAXWindow(axWindows: axWindows, title: title)

        guard let matchedWindow else {
            throw AccessibilityEngineError.axTreeBuildFailed(reason: "Cannot match AX window for window_id \(windowId)")
        }

        return buildAXTree(element: matchedWindow, maxDepth: 8, maxNodes: maxNodes)
    }

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

        guard let matchedWindow = matchAXWindow(axWindows: axWindows, title: title) else {
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

    /// Matches an AXUIElement window from a list of AX windows by title.
    /// Uses exact match, then fuzzy match, then first-window fallback.
    private func matchAXWindow(axWindows: [AXUIElement], title: String?) -> AXUIElement? {
        // Exact title match
        for axWindow in axWindows {
            var axTitleRef: AnyObject?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &axTitleRef)
            let axTitle = axTitleRef as? String

            if let title, let axTitle, axTitle == title {
                return axWindow
            }
        }

        // Fuzzy title match
        for axWindow in axWindows {
            var axTitleRef: AnyObject?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &axTitleRef)
            let axTitle = axTitleRef as? String

            if let title, let axTitle,
               axTitle.lowercased().contains(title.lowercased()) || title.lowercased().contains(axTitle.lowercased()) {
                return axWindow
            }
        }

        // Fallback: first window
        return axWindows.first
    }

    private func raiseAXWindow(pid: Int32, windowId: Int) {
        let axApp = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

        guard axResult == .success, let axWindows = windowsRef as? [AXUIElement] else { return }

        // Find the matching window by looking up the CG window title
        let windowList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        guard let cgWindow = windowList.first(where: {
            $0[kCGWindowNumber as String] as? Int == windowId
        }) else { return }

        let title = cgWindow[kCGWindowName as String] as? String
        guard let matched = matchAXWindow(axWindows: axWindows, title: title) else { return }

        // Raise the window
        let main = true as CFTypeRef
        AXUIElementSetAttributeValue(matched, kAXMainAttribute as CFString, main)
        let focused = true as CFTypeRef
        AXUIElementSetAttributeValue(matched, kAXFocusedAttribute as CFString, focused)
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
        AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &ref)
        let identifier = ref as? String

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
            x: position.x.isFinite ? Int(position.x) : 0,
            y: position.y.isFinite ? Int(position.y) : 0,
            width: size.width.isFinite ? Int(size.width) : 0,
            height: size.height.isFinite ? Int(size.height) : 0
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

        return AXElement(role: role, title: title, value: value, identifier: identifier, bounds: bounds, children: children)
    }

    private func extractAppName(from bundleId: String) -> String? {
        let parts = bundleId.split(separator: ".")
        guard let last = parts.last, !last.isEmpty else { return nil }
        return String(last)
    }
}
