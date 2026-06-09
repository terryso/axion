import Foundation

/// Terminal hyperlink formatter using OSC 8 sequences — inspired by Codex's `terminal_hyperlinks.rs`.
///
/// Makes URLs and file paths clickable (Cmd+Click) in terminals that support OSC 8:
/// `\x1B]8;;{url}\x07{visible text}\x1B]8;;\x07`
///
/// Supported terminals (case-insensitive TERM_PROGRAM matching):
/// - iTerm2 (`iTerm.app`)
/// - Kitty (`kitty`)
/// - WezTerm (`WezTerm`)
/// - Ghostty (`ghostty`)
/// - Warp (`WarpTerminal`)
/// - VS Code integrated terminal (`vscode`)
///
/// Apple Terminal and screen/tmux do NOT support OSC 8 — text is passed through unchanged.
///
/// Example usage:
/// ```swift
/// let fmt = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
/// // Clickable file path:
/// fmt.formatFilePath("/Users/nick/src/main.swift")
/// // → "\x1B]8;;file:///Users/nick/src/main.swift\x07main.swift\x1B]8;;\x07"
///
/// // Clickable URL:
/// fmt.formatURL("https://example.com", visibleText: "docs")
/// // → "\x1B]8;;https://example.com\x07docs\x1B]8;;\x07"
/// ```
struct TerminalHyperlinkFormatter: Sendable {

    /// Whether the current terminal supports OSC 8 hyperlinks.
    let supportsOSC8: Bool

    /// Whether output goes to a TTY.
    let isTTY: Bool

    // MARK: - Initialization

    /// Create a formatter with explicit parameters (for testing).
    ///
    /// - Parameters:
    ///   - isTTY: Whether output goes to a TTY.
    ///   - termProgram: The `TERM_PROGRAM` environment variable value.
    init(
        isTTY: Bool = isatty(STDOUT_FILENO) != 0,
        termProgram: String? = ProcessInfo.processInfo.environment["TERM_PROGRAM"]
    ) {
        self.isTTY = isTTY
        self.supportsOSC8 = isTTY && Self.detectOSC8Support(termProgram: termProgram)
    }

    // MARK: - OSC 8 Detection

    /// Detects whether the terminal supports OSC 8 hyperlinks based on TERM_PROGRAM.
    ///
    /// Known OSC 8 supporters (matching Codex's terminal detection list):
    /// - iTerm2, Kitty, WezTerm, Ghostty, Warp, VS Code
    static func detectOSC8Support(termProgram: String?) -> Bool {
        guard let program = termProgram?.lowercased() else { return false }
        let supportedTerminals: Set<String> = [
            "iterm.app",    // iTerm2
            "kitty",        // Kitty
            "wezterm",      // WezTerm
            "ghostty",      // Ghostty
            "warpterminal", // Warp
            "vscode",       // VS Code integrated terminal
        ]
        return supportedTerminals.contains(program)
    }

    // MARK: - URL Formatting

    /// Wraps a URL in an OSC 8 hyperlink if the terminal supports it.
    ///
    /// Falls back to plain visible text for unsupported terminals.
    /// URLs are sanitized: control characters are removed before encoding.
    ///
    /// - Parameters:
    ///   - url: The target URL (e.g. `https://example.com`).
    ///   - visibleText: The text to display. Defaults to the URL itself.
    /// - Returns: Formatted string with OSC 8 hyperlink or plain text.
    func formatURL(_ url: String, visibleText: String? = nil) -> String {
        let sanitized = sanitizeURL(url)
        guard supportsOSC8, !sanitized.isEmpty else {
            return visibleText ?? url
        }
        let text = visibleText ?? url
        return Self.osc8Wrap(destination: sanitized, text: text)
    }

    /// Wraps a file path in an OSC 8 hyperlink using the `file://` scheme.
    ///
    /// Falls back to plain path for unsupported terminals.
    /// The visible text can optionally be truncated (e.g. showing just the filename).
    ///
    /// - Parameters:
    ///   - path: Absolute or relative file path.
    ///   - visibleText: Optional display text. Defaults to the path itself.
    /// - Returns: Formatted string with OSC 8 hyperlink or plain text.
    func formatFilePath(_ path: String, visibleText: String? = nil) -> String {
        guard supportsOSC8, !path.isEmpty else {
            return visibleText ?? path
        }
        let fileURL = filePathToURL(path)
        let text = visibleText ?? path
        return Self.osc8Wrap(destination: fileURL, text: text)
    }

    // MARK: - Batch Formatting

    /// Formats a line of text, automatically detecting and hyperlinking URLs.
    ///
    /// Scans for `http://` and `https://` URLs and wraps each in an OSC 8 hyperlink.
    /// Non-URL text is passed through unchanged.
    ///
    /// - Parameter text: Input text potentially containing URLs.
    /// - Returns: Text with URLs wrapped in OSC 8 hyperlinks (or unchanged if unsupported).
    func hyperlinkURLs(in text: String) -> String {
        guard supportsOSC8 else { return text }
        return replaceURLs(in: text) { url in
            Self.osc8Wrap(destination: sanitizeURL(url), text: url)
        }
    }

    // MARK: - Escape Sequence Helpers

    /// Wraps visible text in OSC 8 hyperlink escape sequences.
    ///
    /// Format: `\x1B]8;;{destination}\x07{text}\x1B]8;;\x07`
    ///
    /// - Parameters:
    ///   - destination: The URL target.
    ///   - text: The visible display text.
    /// - Returns: OSC 8 encoded string.
    static func osc8Wrap(destination: String, text: String) -> String {
        "\u{1B}]8;;\(destination)\u{07}\(text)\u{1B}]8;;\u{07}"
    }

    // MARK: - Private Helpers

    /// Sanitizes a URL by removing control characters.
    private func sanitizeURL(_ url: String) -> String {
        url.unicodeScalars
            .filter { !$0.properties.isDefaultIgnorableCodePoint && !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Converts a file path to a `file://` URL string.
    ///
    /// - Absolute paths: `file:///Users/nick/src/main.swift`
    /// - Relative paths: `file://./src/main.swift` (best-effort)
    private func filePathToURL(_ path: String) -> String {
        if path.hasPrefix("/") {
            return "file://\(path)"
        } else if path.hasPrefix("~") {
            // Expand ~ to home directory
            let expanded = NSString(string: path).expandingTildeInPath
            return "file://\(expanded)"
        } else {
            return "file://./\(path)"
        }
    }

    /// Replaces URLs in text using a transformation function.
    ///
    /// Uses a simple scanning approach that finds `http://` and `https://` prefixes
    /// and extends to the end of the URL (stopping at whitespace or certain punctuation).
    private func replaceURLs(in text: String, transform: (String) -> String) -> String {
        var result = ""
        var searchStart = text.startIndex

        while searchStart < text.endIndex {
            // Find next URL prefix
            let remaining = text[searchStart...]
            guard let range = remaining.range(of: "https://", options: .literal)
                    ?? remaining.range(of: "http://", options: .literal) else {
                result += String(remaining)
                break
            }

            // Add text before the URL
            result += String(text[searchStart..<range.lowerBound])

            // Find the end of the URL
            let urlStart = range.lowerBound
            let urlEnd = findURLEnd(in: text, from: urlStart)
            let url = String(text[urlStart..<urlEnd])

            // Transform and append
            result += transform(url)

            searchStart = urlEnd
        }

        return result
    }

    /// Finds the end index of a URL starting at the given position.
    ///
    /// URLs end at whitespace or unbalanced trailing punctuation (matching Codex's
    /// `trailing_url_end` logic): `)`, `]`, `}`, `>`, `.`, `,`, `;`, `!`, `'`, `"`.
    private func findURLEnd(in text: String, from start: String.Index) -> String.Index {
        var end = start
        var depthByOpen: [Character: Int] = ["(": 0, "[": 0, "{": 0]

        while end < text.endIndex {
            let char = text[end]

            if char.isWhitespace {
                break
            }

            // Track bracket depth
            switch char {
            case "(": depthByOpen["(", default: 0] += 1
            case ")": depthByOpen["(", default: 0] -= 1
            case "[": depthByOpen["[", default: 0] += 1
            case "]": depthByOpen["[", default: 0] -= 1
            case "{": depthByOpen["{", default: 0] += 1
            case "}": depthByOpen["{", default: 0] -= 1
            default: break
            }

            end = text.index(after: end)
        }

        // Trim trailing punctuation that's likely not part of the URL
        let trailingPunctuation: Set<Character> = [".", ",", ";", "!", "'", "\""]
        while end > start {
            let prev = text.index(before: end)
            let char = text[prev]

            if trailingPunctuation.contains(char) {
                end = prev
            } else if char == ")" && (depthByOpen["("] ?? 0) < 0 {
                depthByOpen["("]! += 1
                end = prev
            } else if char == "]" && (depthByOpen["["] ?? 0) < 0 {
                depthByOpen["["]! += 1
                end = prev
            } else if char == "}" && (depthByOpen["{"] ?? 0) < 0 {
                depthByOpen["{"]! += 1
                end = prev
            } else {
                break
            }
        }

        return end
    }
}
