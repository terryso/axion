import Foundation

/// Result of a security scan on memory content.
enum MemoryScanResult: Equatable, Sendable {
    case safe
    case rejected(reason: String)
    case warning(message: String)
}

/// Pure-struct security scanner for universal memory content.
///
/// Two modes:
/// - **Write-time** (`scan`): Rejects dangerous content before it's persisted.
/// - **Entry-level** (`scanEntry`): Combines write-time checks with invisible Unicode detection.
struct MemorySecurityScanner: Sendable {

    /// Unicode scalar values for invisible characters that should be flagged.
    private static let invisibleScalarValues: [UInt32] = [0x200B, 0x200C, 0x200D, 0xFEFF]

    // MARK: - Write-time scan

    /// Scan content before writing. Returns `.rejected` for threats, `.safe` otherwise.
    func scan(content: String) -> MemoryScanResult {
        let lowered = content.lowercased()

        // Prompt injection
        if matches(lowered, pattern: #"ignore\s+(?:(?:all\s+)?(?:previous|above|prior)\s+instructions|all\s+instructions)"#) {
            return .rejected(reason: "Prompt injection pattern detected")
        }

        // Role hijack
        if matches(lowered, pattern: #"you\s+are\s+now\s+"#) {
            return .rejected(reason: "Role hijack pattern detected")
        }

        // Deception / hiding
        if matches(lowered, pattern: #"do\s+not\s+tell\s+the\s+user"#) {
            return .rejected(reason: "Deception pattern detected")
        }

        // Credential exfiltration via curl
        if matches(lowered, pattern: #"curl\s+.*\$(KEY|TOKEN|SECRET|PASSWORD)"#) {
            return .rejected(reason: "Credential exfiltration pattern detected")
        }

        return .safe
    }

    // MARK: - Entry-level scan (Story 31.4)

    /// Scan a single entry for load-time filtering. Combines write-time and
    /// load-time checks to decide whether the entry should be injected.
    func scanEntry(content: String) -> MemoryScanResult {
        let writeResult = scan(content: content)
        if case .rejected = writeResult { return writeResult }

        for scalarValue in Self.invisibleScalarValues {
            if content.unicodeScalars.contains(where: { $0.value == scalarValue }) {
                return .warning(message: "Invisible Unicode character detected")
            }
        }

        return .safe
    }

    // MARK: - Private

    private func matches(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
