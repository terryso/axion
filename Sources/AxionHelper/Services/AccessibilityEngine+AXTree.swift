import ApplicationServices
import CoreGraphics

extension AccessibilityEngineService {

    // MARK: - AX Tree Building

    func getAXTree(windowId: Int, maxNodes: Int = 500) throws -> AXElement {
        guard let cgWindow = findCGWindow(windowId: windowId) else {
            throw AccessibilityEngineError.windowNotFound(windowId: windowId)
        }

        guard let ownerPID = cgWindow[kCGWindowOwnerPID as String] as? Int32 else {
            throw AccessibilityEngineError.windowNotFound(windowId: windowId)
        }

        let title = cgWindow[kCGWindowName as String] as? String

        guard let axWindows = fetchAXWindows(pid: ownerPID) else {
            throw AccessibilityEngineError.axTreeBuildFailed(reason: "No AX windows found for pid \(ownerPID)")
        }

        guard let matchedWindow = matchAXWindow(axWindows: axWindows, title: title) else {
            throw AccessibilityEngineError.axTreeBuildFailed(reason: "Cannot match AX window for window_id \(windowId)")
        }

        return buildAXTree(element: matchedWindow, maxDepth: 8, maxNodes: maxNodes)
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

        let center: ElementCenter? = (bounds.width > 0 && bounds.height > 0)
            ? ElementCenter(x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2)
            : nil

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

        return AXElement(role: role, title: title, value: value, identifier: identifier, bounds: bounds, center: center, children: children)
    }

    // MARK: - AX Window Matching

    /// Matches an AXUIElement window from a list of AX windows by title.
    /// Uses exact match, then fuzzy match, then first-window fallback.
    func matchAXWindow(axWindows: [AXUIElement], title: String?) -> AXUIElement? {
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

    // MARK: - AX Window Raising

    func raiseAXWindow(pid: Int32, windowId: Int) {
        guard let axWindows = fetchAXWindows(pid: pid) else { return }

        // Find the matching window by looking up the CG window title
        guard let cgWindow = findCGWindow(windowId: windowId) else { return }

        let title = cgWindow[kCGWindowName as String] as? String
        guard let matched = matchAXWindow(axWindows: axWindows, title: title) else { return }

        // Raise the window
        let main = true as CFTypeRef
        AXUIElementSetAttributeValue(matched, kAXMainAttribute as CFString, main)
        let focused = true as CFTypeRef
        AXUIElementSetAttributeValue(matched, kAXFocusedAttribute as CFString, focused)
    }
}
