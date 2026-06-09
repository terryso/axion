import AppKit
import AxionCore
import CoreGraphics
import Foundation

/// Errors thrown by `EventRecorderService`.
enum EventRecorderError: Error, LocalizedError, ToolErrorProtocol {
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

    var events: [RecordedEvent] = []
    var isRecordingFlag = false
    var startTime: Date?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    var windowContextCache: WindowContext?
    private var contextTimer: Timer?
    var currentModifiers: CGEventFlags = []
    var windowSnapshots: [WindowSnapshot] = []
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

    // MARK: - Window Context Helpers

    /// Creates a WindowContext from the given running application.
    private func makeWindowContext(from app: NSRunningApplication) -> WindowContext {
        let appName = app.localizedName ?? "Unknown"
        let pid = app.processIdentifier
        return WindowContext(appName: appName, pid: Int32(pid), windowId: Int(pid), windowTitle: appName)
    }

    // MARK: - Window Context Sampling

    private func refreshWindowContext() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        windowContextCache = makeWindowContext(from: app)
    }

    // MARK: - Window Snapshot Sampling

    var snapshotIndex = 0

    private func captureWindowSnapshot() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let context = makeWindowContext(from: app)
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let snapshot = AxionCore.WindowSnapshot(
            windowId: context.windowId,
            appName: context.appName,
            title: context.windowTitle,
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

            let context = self.makeWindowContext(from: app)
            var params: [String: JSONValue] = [
                "app_name": .string(context.appName),
                "pid": .int(Int(context.pid)),
            ]
            if let bundleId = app.bundleIdentifier {
                params["bundle_id"] = .string(bundleId)
            }

            self.appendEvent(
                type: .appSwitch,
                timestamp: Double(elapsed),
                parameters: params
            )

            // Update context cache immediately on app switch
            self.windowContextCache = context
        }
    }

    private func unregisterAppSwitchObserver() {
        if let observer = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appSwitchObserver = nil
        }
    }
}
