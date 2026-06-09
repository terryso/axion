import Foundation

// MARK: - Utility Helpers

extension RunOrchestrator {

    // MARK: - ID & Config Helpers

    /// Generates a unique run ID in the format `YYYYMMDD-{6random}`.
    static func generateRunId() -> String {
        let datePart = axionRunIdDateFormatter.string(from: Date())
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        let randomPart = String((0..<6).map { _ in chars.randomElement()! })
        return "\(datePart)-\(randomPart)"
    }

    /// Parses a skill name from a task that starts with `/`.
    static func parseSkillName(from task: String) -> String? {
        guard task.hasPrefix("/") else { return nil }
        let afterSlash = task.dropFirst()
        let name = afterSlash.split(separator: " ", maxSplits: 1).first.map(String.init) ?? String(afterSlash)
        return name.isEmpty ? nil : name
    }

    /// Computes the effective max steps for the agent loop.
    /// In fast mode, caps at 5 to reduce LLM calls (NFR28).
    static func computeEffectiveMaxSteps(fast: Bool, maxSteps: Int?, configMaxSteps: Int) -> Int {
        if fast {
            return min(maxSteps ?? configMaxSteps, 5)
        }
        return maxSteps ?? configMaxSteps
    }

    /// Computes the effective max tokens for the agent loop.
    /// In fast mode, reduces to 2048 to limit output token consumption.
    static func computeEffectiveMaxTokens(fast: Bool) -> Int {
        return fast ? 2048 : 4096
    }

    /// Computes the run mode string for trace and output handlers.
    /// Fast takes priority over dryrun when both are set.
    static func traceMode(fast: Bool, dryrun: Bool) -> String {
        return fast ? "fast" : (dryrun ? "dryrun" : "standard")
    }

    // MARK: - Content Extraction

    /// Extracts bundle_id from a launch_app tool result JSON (used for app activation).
    static func extractBundleIdFromLaunchResult(_ content: String) -> String? {
        guard let json = parseJSONDict(from: content) else {
            return nil
        }
        return json["bundle_id"] as? String
    }

    /// Extracts the skill name from a Skill tool's JSON input.
    static func extractSkillName(from input: String) -> String? {
        guard let json = parseJSONDict(from: input) else {
            return nil
        }
        return json["skill"] as? String
    }

    // MARK: - App Activation & Notifications

    /// Activates an app using osascript with bundle id — runs from the CLI process (terminal) where it has permission.
    static func activateAppFromCLI(bundleId: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application id \"\(bundleId)\" to activate"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("[RunOrchestrator] osascript activate failed for \(bundleId): \(error)")
        }
    }

    /// Sends a macOS desktop notification via osascript.
    /// Uses `display notification` which works without any entitlements or bundle ID.
    /// Blocks briefly (~50ms) to ensure the notification fires before process exit.
    static func sendDesktopNotification(title: String, subtitle: String? = nil, message: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let escapedTitle = escapeAppleScript(title)
        let escapedMessage = escapeAppleScript(message)
        var script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\""
        if let subtitle {
            script += " subtitle \"\(escapeAppleScript(subtitle))\""
        }
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {}
    }

    /// Escapes backslashes and double quotes for AppleScript string literals.
    private static func escapeAppleScript(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
