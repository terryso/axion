import AppKit
import CoreGraphics

extension InputSimulationService {

    // MARK: - Mouse Operations

    func click(x: Int, y: Int) throws {
        try validateCoordinates(x: x, y: y)
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        downEvent?.post(tap: .cghidEventTap)

        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        upEvent?.post(tap: .cghidEventTap)
    }

    func doubleClick(x: Int, y: Int) throws {
        try validateCoordinates(x: x, y: y)
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))

        // First click
        let down1 = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        down1?.setIntegerValueField(.mouseEventClickState, value: 1)
        down1?.post(tap: .cghidEventTap)

        let up1 = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        up1?.setIntegerValueField(.mouseEventClickState, value: 1)
        up1?.post(tap: .cghidEventTap)

        // Second click with clickState = 2
        let down2 = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        down2?.setIntegerValueField(.mouseEventClickState, value: 2)
        down2?.post(tap: .cghidEventTap)

        let up2 = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        up2?.setIntegerValueField(.mouseEventClickState, value: 2)
        up2?.post(tap: .cghidEventTap)
    }

    func rightClick(x: Int, y: Int) throws {
        try validateCoordinates(x: x, y: y)
        let point = CGPoint(x: CGFloat(x), y: CGFloat(y))

        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        downEvent?.post(tap: .cghidEventTap)

        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        upEvent?.post(tap: .cghidEventTap)
    }

    func scroll(direction: String, amount: Int) throws {
        let event: CGEvent?
        switch direction.lowercased() {
        case "up":
            event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: Int32(amount),
                wheel2: 0,
                wheel3: 0
            )
        case "down":
            event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 1,
                wheel1: Int32(-amount),
                wheel2: 0,
                wheel3: 0
            )
        case "left":
            event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: Int32(-amount),
                wheel3: 0
            )
        case "right":
            event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: 0,
                wheel2: Int32(amount),
                wheel3: 0
            )
        default:
            throw InputSimulationError.invalidDirection(direction)
        }
        event?.post(tap: .cghidEventTap)
    }

    func drag(fromX: Int, fromY: Int, toX: Int, toY: Int) throws {
        try validateCoordinates(x: fromX, y: fromY)
        try validateCoordinates(x: toX, y: toY)

        let start = CGPoint(x: CGFloat(fromX), y: CGFloat(fromY))
        let end = CGPoint(x: CGFloat(toX), y: CGFloat(toY))

        // Move to start position
        let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: start,
            mouseButton: .left
        )
        moveEvent?.post(tap: .cghidEventTap)

        // Mouse down at start
        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: start,
            mouseButton: .left
        )
        downEvent?.post(tap: .cghidEventTap)

        // Smooth drag with interpolated intermediate points
        let distance = hypot(end.x - start.x, end.y - start.y)
        let steps = max(10, Int(distance / 20))

        var prevX = start.x
        var prevY = start.y

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t

            let dragEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: .left
            )
            dragEvent?.setIntegerValueField(.mouseEventDeltaX, value: Int64(x - prevX))
            dragEvent?.setIntegerValueField(.mouseEventDeltaY, value: Int64(y - prevY))
            dragEvent?.post(tap: .cghidEventTap)

            prevX = x
            prevY = y
        }

        // Mouse up at end
        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: end,
            mouseButton: .left
        )
        upEvent?.post(tap: .cghidEventTap)
    }
}
