import AppKit
import AxionCore
import CoreGraphics
import Foundation

/// Errors thrown by `EventRecorderService`.
enum EventRecorderError: Error, LocalizedError {
    case tapCreationFailed
    case alreadyRecording
    case notRecording

    var errorDescription: String? {
        switch self {
        case .tapCreationFailed:
            return "Failed to create CGEvent tap. Ensure Accessibility permissions are granted."
        case .alreadyRecording:
            return "Recording is already in progress."
        case .notRecording:
            return "No recording in progress."
        }
    }

    var errorCode: String {
        switch self {
        case .tapCreationFailed: return "tap_creation_failed"
        case .alreadyRecording: return "already_recording"
        case .notRecording: return "not_recording"
        }
    }

    var suggestion: String {
        switch self {
        case .tapCreationFailed: return "Run 'axion doctor' to verify Accessibility permissions."
        case .alreadyRecording: return "Stop the current recording before starting a new one."
        case .notRecording: return "Call startRecording() first."
        }
    }
}

/// Records desktop events using CGEvent Tap (listen-only) and NSWorkspace notifications.
///
/// Performance note (NFR33): CGEvent callback only captures type, coordinates/keycode, and timestamp.
/// Window context is sampled via a 500ms timer to avoid expensive AX queries in the hot path.
final class EventRecorderService: EventRecording, @unchecked Sendable {

    // MARK: - State

    private var events: [RecordedEvent] = []
    private var isRecordingFlag = false
    private var startTime: Date?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var windowContextCache: WindowContext?
    private var contextTimer: Timer?
    private var currentModifiers: CGEventFlags = []
    private var windowSnapshots: [WindowSnapshot] = []
    private var snapshotTimer: Timer?

    // MARK: - EventRecording Protocol

    var isRecording: Bool { isRecordingFlag }

    func startRecording() throws {
        guard !isRecordingFlag else {
            throw EventRecorderError.alreadyRecording
        }

        events = []
        windowSnapshots = []
        startTime = Date()
        isRecordingFlag = true

        // Start window context sampling (every 500ms)
        refreshWindowContext()
        contextTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshWindowContext()
        }

        // Start window snapshot sampling (every 2s)
        captureWindowSnapshot()
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.captureWindowSnapshot()
        }

        // Start CGEvent tap
        try createEventTap()

        // Start NSWorkspace observer for app switches
        registerAppSwitchObserver()
    }

    func stopRecording() -> RecordingResult {
        guard isRecordingFlag else { return RecordingResult(events: [], windowSnapshots: []) }

        isRecordingFlag = false
        contextTimer?.invalidate()
        contextTimer = nil
        snapshotTimer?.invalidate()
        snapshotTimer = nil

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let rlSource = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), rlSource, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }

        unregisterAppSwitchObserver()

        let resultEvents = events
        let resultSnapshots = windowSnapshots
        events = []
        windowSnapshots = []
        return RecordingResult(events: resultEvents, windowSnapshots: resultSnapshots)
    }

    // MARK: - CGEvent Tap

    private func createEventTap() throws {
        let eventMask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<EventRecorderService>.fromOpaque(refcon).takeUnretainedValue()
                service.handleEvent(event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isRecordingFlag = false
            contextTimer?.invalidate()
            contextTimer = nil
            snapshotTimer?.invalidate()
            snapshotTimer = nil
            throw EventRecorderError.tapCreationFailed
        }

        eventTap = tap
        CGEvent.tapEnable(tap: tap, enable: true)

        let rlSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = rlSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), rlSource, .commonModes)
    }

    // MARK: - Event Handling (called from CGEvent callback — must be lightweight)

    private func handleEvent(_ cgEvent: CGEvent) {
        guard isRecordingFlag else { return }

        let timestamp = startTime.map { Date().timeIntervalSince($0) } ?? 0

        let eventType = cgEvent.type

        switch eventType {
        case .leftMouseDown:
            let x = Int(cgEvent.location.x)
            let y = Int(cgEvent.location.y)
            appendEvent(
                type: .click,
                timestamp: timestamp,
                parameters: ["x": .int(x), "y": .int(y)]
            )

        case .keyDown:
            let keyCode = CGKeyCode(cgEvent.getIntegerValueField(.keyboardEventKeycode))
            let chars = charactersFromEvent(cgEvent, keyCode: keyCode)
            let flags = cgEvent.flags

            // Detect modifier-only combinations as hotkey
            if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
                let keyName = keyNameFromKeyCode(keyCode)
                let mods = modifierString(flags)
                appendEvent(
                    type: .hotkey,
                    timestamp: timestamp,
                    parameters: ["keys": .string("\(mods)\(keyName)")]
                )
            } else if let chars {
                appendEvent(
                    type: .typeText,
                    timestamp: timestamp,
                    parameters: ["text": .string(chars)]
                )
            }

        case .scrollWheel:
            let delta = Int(cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            let direction = delta > 0 ? "up" : "down"
            let amount = abs(delta)
            if amount > 0 {
                appendEvent(
                    type: .scroll,
                    timestamp: timestamp,
                    parameters: ["direction": .string(direction), "amount": .int(amount)]
                )
            }

        case .flagsChanged:
            currentModifiers = cgEvent.flags

        default:
            break
        }
    }

    private func appendEvent(type: RecordedEvent.EventType, timestamp: TimeInterval, parameters: [String: JSONValue]) {
        let event = RecordedEvent(type: type, timestamp: timestamp, parameters: parameters, windowContext: windowContextCache)
        events.append(event)
    }

    // MARK: - Key Mapping

    private func charactersFromEvent(_ event: CGEvent, keyCode: CGKeyCode) -> String? {
        // Use the event's Unicode string (accounts for current input source)
        var length: Int = 0
        var chars: UniChar = 0
        event.keyboardGetUnicodeString(maxStringLength: 1, actualStringLength: &length, unicodeString: &chars)
        guard length > 0, let scalar = Unicode.Scalar(chars) else { return nil }
        let char = Character(scalar)
        // Filter out control characters
        guard char.isLetter || char.isNumber || char.isSymbol || char.isPunctuation else { return nil }
        guard !char.isNewline else { return nil }
        return String(char)
    }

    private func keyNameFromKeyCode(_ keyCode: CGKeyCode) -> String {
        // Reverse lookup from InputSimulationService.keyMap
        let keyMap: [CGKeyCode: String] = [
            0x24: "return", 0x30: "tab", 0x31: "space", 0x35: "escape",
            0x33: "delete", 0x75: "forwarddelete", 0x73: "home", 0x77: "end",
            0x74: "pageup", 0x79: "pagedown",
            0x7B: "left", 0x7C: "right", 0x7D: "down", 0x7E: "up",
            0x7A: "f1", 0x78: "f2", 0x63: "f3", 0x76: "f4",
            0x60: "f5", 0x61: "f6", 0x62: "f7", 0x64: "f8",
            0x65: "f9", 0x6D: "f10", 0x67: "f11", 0x6F: "f12",
            0x00: "a", 0x0B: "b", 0x08: "c", 0x02: "d", 0x0E: "e",
            0x03: "f", 0x05: "g", 0x04: "h", 0x22: "i", 0x26: "j",
            0x28: "k", 0x25: "l", 0x2E: "m", 0x2D: "n", 0x1F: "o",
            0x23: "p", 0x0C: "q", 0x0F: "r", 0x01: "s", 0x11: "t",
            0x20: "u", 0x09: "v", 0x0D: "w", 0x07: "x", 0x10: "y",
            0x06: "z",
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
            0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
            0x21: "[", 0x1E: "]", 0x29: ";", 0x2C: ",", 0x2F: ".",
            0x2B: "/", 0x27: "'", 0x18: "=", 0x32: "`", 0x2A: "\\",
            0x0A: "-",
        ]
        return keyMap[keyCode] ?? "key_\(keyCode)"
    }

    private func modifierString(_ flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskCommand) { parts.append("cmd+") }
        if flags.contains(.maskShift) { parts.append("shift+") }
        if flags.contains(.maskControl) { parts.append("ctrl+") }
        if flags.contains(.maskAlternate) { parts.append("alt+") }
        return parts.joined()
    }

    // MARK: - Window Context Sampling

    private func refreshWindowContext() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"
        let windowTitle = appName
        // Use pid hash as a stable window identifier
        let windowId = Int(pid)
        windowContextCache = WindowContext(appName: appName, pid: Int32(pid), windowId: windowId, windowTitle: windowTitle)
    }

    // MARK: - Window Snapshot Sampling

    private var snapshotIndex = 0

    private func captureWindowSnapshot() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"
        let windowId = Int(pid)
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let snapshot = AxionCore.WindowSnapshot(
            windowId: windowId,
            appName: appName,
            title: appName,
            bounds: AxionCore.WindowBounds(
                x: Int(screenRect.origin.x),
                y: Int(screenRect.origin.y),
                width: Int(screenRect.width),
                height: Int(screenRect.height)
            ),
            capturedAtEventIndex: snapshotIndex
        )
        windowSnapshots.append(snapshot)
        snapshotIndex = events.count
    }

    // MARK: - App Switch Observer

    private var appSwitchObserver: NSObjectProtocol?

    private func registerAppSwitchObserver() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, self.isRecordingFlag else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

            let elapsed = self.startTime.map { Date().timeIntervalSince($0) } ?? 0
            let timestamp = Double(elapsed)

            let appName = app.localizedName ?? "Unknown"
            let pid = app.processIdentifier

            self.appendEvent(
                type: .appSwitch,
                timestamp: timestamp,
                parameters: ["app_name": .string(appName), "pid": .int(Int(pid))]
            )

            // Update context cache immediately on app switch
            self.windowContextCache = WindowContext(
                appName: appName, pid: Int32(pid),
                windowId: Int(pid),
                windowTitle: appName
            )
        }
    }

    private func unregisterAppSwitchObserver() {
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }
    }
}
