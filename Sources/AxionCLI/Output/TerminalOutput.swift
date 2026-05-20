import Foundation
// MARK: - TerminalOutput

/// Outputs human-readable progress information to the terminal during task execution.
/// Uses an injectable `write` closure (defaults to `print`) for testability.
///
/// Format conventions:
/// - Every line is prefixed with `[axion]`
/// - Step progress: `步骤 {current}/{total}: {tool} — {status}`
/// - Status markers: `ok` (success), `x {reason}` (failure)
/// - No emoji — pure ASCII for terminal/pipeline compatibility
final class TerminalOutput {

    let write: (String) -> Void

    init(write: @escaping (String) -> Void = {
        fputs($0 + "\n", stdout)
        fflush(stdout)
    }) {
        self.write = write
    }

    /// Writes streaming text inline without a trailing newline (typewriter effect).
    func writeStream(_ text: String) {
        Swift.print(text, terminator: "")
        fflush(stdout)
    }

    /// Ends the current streaming line (prints newline if mid-stream).
    func endStream() {
        Swift.print("")
    }

    func displayRunStart(runId: String, task: String, mode: String) {
        write("[axion] \u{6A21}\u{5F0F}: \(mode)")
        write("[axion] \u{8FD0}\u{884C} ID: \(runId)")
        write("[axion] \u{4EFB}\u{52A1}: \(task)")
    }
}
