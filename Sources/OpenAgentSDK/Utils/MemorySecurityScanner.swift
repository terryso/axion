import Foundation

/// Stateless security scanner that validates experience signals and memory facts
/// before they are persisted.
///
/// Checks content length, blocked domains, blocked patterns (regex), and
/// confidence ceiling. Rejection order is deterministic:
/// content length -> blocked domain -> blocked pattern -> confidence ceiling.
public struct MemorySecurityScanner: Sendable {

    public let config: MemorySecurityConfig

    /// Compiled regex patterns paired with their original pattern strings.
    /// Invalid patterns are silently skipped (logged as warnings).
    private let compiledPatterns: [(regex: NSRegularExpression, original: String)]

    public init(config: MemorySecurityConfig = MemorySecurityConfig()) {
        self.config = config
        var compiled: [(regex: NSRegularExpression, original: String)] = []
        for pattern in config.blockedPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                compiled.append((regex: regex, original: pattern))
            } catch {
                Logger.shared.warn("MemorySecurityScanner", "invalid_regex_pattern", data: [
                    "pattern": pattern,
                    "error": error.localizedDescription,
                ])
            }
        }
        self.compiledPatterns = compiled
    }

    /// Scan an experience signal against security rules.
    public func scan(signal: ExperienceSignal) -> SecurityScanResult {
        scan(content: signal.content, domain: signal.domain, confidence: signal.confidence)
    }

    /// Scan a memory fact against security rules.
    public func scan(fact: MemoryFact) -> SecurityScanResult {
        scan(content: fact.content, domain: fact.domain, confidence: fact.confidence)
    }

    // MARK: - Private

    private func scan(content: String, domain: String, confidence: Double) -> SecurityScanResult {
        // 1. Content length
        if content.count > config.maxContentLength {
            return .rejected(reason: "Content exceeds maximum length (\(content.count) > \(config.maxContentLength))")
        }

        // 2. Blocked domain
        for blocked in config.blockedDomains {
            if domain.caseInsensitiveCompare(blocked) == .orderedSame {
                return .rejected(reason: "Domain is blocked: \(blocked)")
            }
        }

        // 3. Blocked patterns
        for entry in compiledPatterns {
            let range = NSRange(content.startIndex..., in: content)
            if entry.regex.firstMatch(in: content, options: [], range: range) != nil {
                return .rejected(reason: "Content matches blocked pattern: \(entry.original)")
            }
        }

        // 4. Confidence ceiling
        if confidence > config.maxConfidence {
            return .rejected(reason: "Confidence exceeds maximum allowed (\(confidence) > \(config.maxConfidence))")
        }

        return .passed
    }
}
