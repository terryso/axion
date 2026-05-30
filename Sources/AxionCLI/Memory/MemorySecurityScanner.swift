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
/// - **Load-time** (`scanOnLoad`): Returns warnings for suspicious entries without blocking.
struct MemorySecurityScanner: Sendable {

    /// Unicode scalar values for invisible characters that should be flagged.
    private static let invisibleScalarValues: [UInt32] = [0x200B, 0x200C, 0x200D, 0xFEFF]

    // MARK: - Write-time scan

    /// Scan content before writing. Returns `.rejected` for threats, `.safe` otherwise.
    func scan(content: String) -> MemoryScanResult {
        let lowered = content.lowercased()

        // Prompt injection
        if matches(lowered, pattern: #"ignore\s+(previous|all|above|prior)\s+instructions"#) {
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

    // MARK: - Load-time scan

    /// Scan persisted content at load time. Returns a list of warning strings
    /// for suspicious entries. Does NOT block loading.
    func scanOnLoad(content: String) -> [String] {
        var warnings: [String] = []

        // Invisible Unicode detection (zero-width characters, BOM)
        for scalarValue in Self.invisibleScalarValues {
            if content.unicodeScalars.contains(where: { $0.value == scalarValue }) {
                warnings.append("Invisible Unicode character detected")
                break
            }
        }

        let lowered = content.lowercased()

        // Prompt injection (warn, don't block)
        if matches(lowered, pattern: #"ignore\s+(previous|all|above|prior)\s+instructions"#) {
            warnings.append("Prompt injection pattern detected in stored memory")
        }

        // Role hijack
        if matches(lowered, pattern: #"you\s+are\s+now\s+"#) {
            warnings.append("Role hijack pattern detected in stored memory")
        }

        // Deception / hiding
        if matches(lowered, pattern: #"do\s+not\s+tell\s+the\s+user"#) {
            warnings.append("Deception pattern detected in stored memory")
        }

        // Credential exfiltration
        if matches(lowered, pattern: #"curl\s+.*\$(KEY|TOKEN|SECRET|PASSWORD)"#) {
            warnings.append("Credential exfiltration pattern detected in stored memory")
        }

        return warnings
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
