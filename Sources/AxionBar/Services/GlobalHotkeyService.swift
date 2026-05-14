@preconcurrency import ApplicationServices
import AppKit
import Foundation
import os.log

// Nonisolated helpers to wrap concurrency-unsafe C APIs.
nonisolated func _axIsProcessTrusted() -> Bool {
    AXIsProcessTrusted()
}

nonisolated func _axPromptTrust() {
    // kAXTrustedCheckOptionPrompt wraps to "AXTrustedCheckOptionPrompt" in CFString
    // Use the raw string to avoid Unmanaged<CFString> bridging issues
    let key = "AXTrustedCheckOptionPrompt" as CFString
    let options = [key: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
}

@MainActor
final class GlobalHotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let logger = Logger(subsystem: "com.axion.AxionBar", category: "GlobalHotkeyService")

    var onHotkeyTriggered: ((HotkeyBinding) -> Void)?

    // MARK: - Accessibility

    nonisolated static func checkAccessibilityPermission() -> Bool {
        _axIsProcessTrusted()
    }

    nonisolated static func promptAccessibilityPermission() {
        _axPromptTrust()
    }

    // MARK: - Start / Stop

    func start(configManager: HotkeyConfigManager) {
        stop()
        guard !configManager.bindings.isEmpty else { return }

        // Global monitor — fires for events in OTHER applications
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event, configManager: configManager)
            }
        }

        // Local monitor — fires for events in OUR application
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            self.handleKeyEvent(event, configManager: configManager)
            return event
        }
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // MARK: - Private

    private func handleKeyEvent(_ event: NSEvent, configManager: HotkeyConfigManager) {
        guard let binding = configManager.findBinding(event: event) else { return }
        logger.info("Hotkey triggered: \(binding.displayString)")
        onHotkeyTriggered?(binding)
    }
}
