import Foundation
import Testing

@testable import AxionCLI

@Suite("TerminalHyperlinkFormatter")
struct TerminalHyperlinkFormatterTests {

    // MARK: - OSC 8 Support Detection

    @Test("OSC 8 supported for known terminals")
    func osc8SupportedTerminals() {
        let supported = [
            "iTerm.app", "kitty", "WezTerm", "ghostty", "WarpTerminal", "vscode",
        ]
        for program in supported {
            #expect(
                TerminalHyperlinkFormatter.detectOSC8Support(termProgram: program),
                "\(program) should support OSC 8"
            )
        }
    }

    @Test("OSC 8 not supported for unknown terminals")
    func osc8NotSupportedUnknownTerminals() {
        let unsupported: [String?] = [
            "Apple_Terminal", "alacritty", "xterm-256color", "screen", nil, "",
        ]
        for program in unsupported {
            #expect(
                !TerminalHyperlinkFormatter.detectOSC8Support(termProgram: program),
                "\(program ?? "nil") should not support OSC 8"
            )
        }
    }

    @Test("OSC 8 detection is case-insensitive")
    func osc8CaseInsensitive() {
        #expect(TerminalHyperlinkFormatter.detectOSC8Support(termProgram: "ITERM.APP"))
        #expect(TerminalHyperlinkFormatter.detectOSC8Support(termProgram: "KITTY"))
        #expect(TerminalHyperlinkFormatter.detectOSC8Support(termProgram: "WEZTERM"))
        #expect(TerminalHyperlinkFormatter.detectOSC8Support(termProgram: "GHOSTTY"))
    }

    @Test("Non-TTY disables OSC 8 even for supported terminals")
    func nonTTYDisablesOSC8() {
        let formatter = TerminalHyperlinkFormatter(isTTY: false, termProgram: "iTerm.app")
        #expect(!formatter.supportsOSC8)
        #expect(!formatter.isTTY)
    }

    // MARK: - osc8Wrap Static Helper

    @Test("osc8Wrap produces correct escape sequence")
    func osc8WrapSequence() {
        let result = TerminalHyperlinkFormatter.osc8Wrap(
            destination: "https://example.com",
            text: "click here"
        )
        #expect(result == "\u{1B}]8;;https://example.com\u{07}click here\u{1B}]8;;\u{07}")
    }

    @Test("osc8Wrap with file URL")
    func osc8WrapFileURL() {
        let result = TerminalHyperlinkFormatter.osc8Wrap(
            destination: "file:///Users/nick/src/main.swift",
            text: "main.swift"
        )
        #expect(result.contains("\u{1B}]8;;file:///Users/nick/src/main.swift\u{07}"))
        #expect(result.contains("main.swift"))
        #expect(result.hasSuffix("\u{1B}]8;;\u{07}"))
    }

    // MARK: - formatURL

    @Test("formatURL wraps URL when OSC 8 supported")
    func formatURLSupported() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let result = formatter.formatURL("https://example.com")
        #expect(result.contains("\u{1B}]8;;https://example.com\u{07}"))
        #expect(result.contains("https://example.com"))
    }

    @Test("formatURL with custom visible text")
    func formatURLCustomText() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "kitty")
        let result = formatter.formatURL("https://example.com", visibleText: "docs")
        #expect(result.contains("\u{1B}]8;;https://example.com\u{07}docs\u{1B}]8;;\u{07}"))
    }

    @Test("formatURL falls back to plain text when OSC 8 not supported")
    func formatURLFallback() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "Apple_Terminal")
        let result = formatter.formatURL("https://example.com")
        #expect(result == "https://example.com")
        #expect(!result.contains("\u{1B}"))
    }

    @Test("formatURL falls back to visible text when unsupported")
    func formatURLFallbackCustomText() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "screen")
        let result = formatter.formatURL("https://example.com", visibleText: "docs")
        #expect(result == "docs")
    }

    @Test("formatURL sanitizes control characters")
    func formatURLSanitizesControlChars() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let url = "https://example.com/path\u{07}\u{1B}"
        let result = formatter.formatURL(url)
        // Control chars (BEL \x07, ESC \x1B) should be stripped from the destination URL.
        // The OSC 8 sequence uses BEL as delimiter, so we check the destination part specifically.
        // The destination (between ]8;; and the first \x07) should not contain extra BEL/ESC chars.
        let destStart = "\u{1B}]8;;"
        if let range = result.range(of: destStart) {
            let afterPrefix = result[range.upperBound...]
            // Find the BEL that closes the destination
            if let belIdx = afterPrefix.firstIndex(of: "\u{07}") {
                let destination = String(afterPrefix[..<belIdx])
                // The destination should be clean — just the URL without control chars
                #expect(destination == "https://example.com/path")
                #expect(!destination.contains("\u{1B}"))
            }
        }
    }

    // MARK: - formatFilePath

    @Test("formatFilePath wraps absolute path with file:// scheme")
    func formatFilePathAbsolute() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let result = formatter.formatFilePath("/Users/nick/src/main.swift")
        #expect(result.contains("\u{1B}]8;;file:///Users/nick/src/main.swift\u{07}"))
        #expect(result.contains("main.swift"))
    }

    @Test("formatFilePath with custom visible text (truncated)")
    func formatFilePathTruncated() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "WezTerm")
        let result = formatter.formatFilePath(
            "/Users/nick/src/main.swift",
            visibleText: "main.swift"
        )
        #expect(result.contains("\u{1B}]8;;file:///Users/nick/src/main.swift\u{07}"))
        #expect(result.contains("main.swift"))
        // The visible text is "main.swift", not the full path
        #expect(result.contains("main.swift\u{1B}]8;;\u{07}"))
    }

    @Test("formatFilePath falls back to plain path when OSC 8 not supported")
    func formatFilePathFallback() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "alacritty")
        let result = formatter.formatFilePath("/Users/nick/src/main.swift")
        #expect(result == "/Users/nick/src/main.swift")
        #expect(!result.contains("\u{1B}"))
    }

    @Test("formatFilePath falls back to visible text when unsupported")
    func formatFilePathFallbackCustomText() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "alacritty")
        let result = formatter.formatFilePath(
            "/Users/nick/src/main.swift",
            visibleText: "main.swift"
        )
        #expect(result == "main.swift")
    }

    @Test("formatFilePath expands tilde in destination but keeps tilde in visible text")
    func formatFilePathTilde() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "ghostty")
        let result = formatter.formatFilePath("~/src/main.swift")
        // The file:// destination should have expanded ~ to home directory
        #expect(result.contains("file://"))
        // The visible text is the original path (with ~), but destination is expanded
        let homeDir = NSString(string: "~/src/main.swift").expandingTildeInPath
        #expect(result.contains("file://\(homeDir)"))
    }

    @Test("formatFilePath handles relative paths")
    func formatFilePathRelative() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let result = formatter.formatFilePath("src/main.swift")
        #expect(result.contains("file://./src/main.swift"))
    }

    @Test("formatFilePath handles empty path")
    func formatFilePathEmpty() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let result = formatter.formatFilePath("")
        #expect(result == "")
    }

    // MARK: - hyperlinkURLs

    @Test("hyperlinkURLs wraps URLs in text")
    func hyperlinkURLsBasic() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let text = "See https://example.com for details"
        let result = formatter.hyperlinkURLs(in: text)
        #expect(result.contains("\u{1B}]8;;https://example.com\u{07}https://example.com\u{1B}]8;;\u{07}"))
        #expect(result.contains("See "))
        #expect(result.contains(" for details"))
    }

    @Test("hyperlinkURLs handles multiple URLs")
    func hyperlinkURLsMultiple() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "kitty")
        let text = "Visit https://a.com and http://b.org"
        let result = formatter.hyperlinkURLs(in: text)
        #expect(result.contains("\u{1B}]8;;https://a.com\u{07}"))
        #expect(result.contains("\u{1B}]8;;http://b.org\u{07}"))
    }

    @Test("hyperlinkURLs strips trailing punctuation from URLs")
    func hyperlinkURLsTrailingPunctuation() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let text = "See (https://example.com/path)."
        let result = formatter.hyperlinkURLs(in: text)
        // The closing ) and . should NOT be part of the URL
        let urlRange = result.range(of: "https://example.com/path")
        #expect(urlRange != nil)
        // The destination should not contain trailing ).
        #expect(result.contains("\u{1B}]8;;https://example.com/path\u{07}"))
    }

    @Test("hyperlinkURLs returns unchanged text when OSC 8 not supported")
    func hyperlinkURLsUnsupported() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "Apple_Terminal")
        let text = "See https://example.com for details"
        let result = formatter.hyperlinkURLs(in: text)
        #expect(result == text)
    }

    @Test("hyperlinkURLs returns unchanged text with no URLs")
    func hyperlinkURLsNoURLs() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let text = "No URLs here, just plain text."
        let result = formatter.hyperlinkURLs(in: text)
        #expect(result == text)
    }

    // MARK: - Integration with TurnFileChangeTracker

    @Test("TurnFileChangeTracker and TerminalHyperlinkFormatter work together")
    func turnFileChangeTrackerWithHyperlinks() {
        // This test validates that TerminalHyperlinkFormatter can be used alongside
        // TurnFileChangeTracker output. The tracker renders file paths, and the
        // formatter makes them clickable.
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        #expect(formatter.supportsOSC8)

        // Verify the formatter can create clickable links for paths that the tracker outputs
        let linkedPath = formatter.formatFilePath(
            "/Users/nick/src/main.swift",
            visibleText: "main.swift"
        )
        #expect(linkedPath.contains("file:///Users/nick/src/main.swift"))
        #expect(linkedPath.contains("main.swift"))
    }

    // MARK: - Edge Cases

    @Test("Empty string URL returns empty or original text")
    func emptyURL() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let result = formatter.formatURL("", visibleText: "link")
        #expect(result == "link")
    }

    @Test("URL with query parameters and fragments")
    func urlWithQueryAndFragment() {
        let formatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let result = formatter.formatURL("https://example.com/path?q=test#section")
        #expect(result.contains("\u{1B}]8;;https://example.com/path?q=test#section\u{07}"))
    }

    @Test("Non-TTY formatter returns plain text for all methods")
    func nonTTYPlainText() {
        let formatter = TerminalHyperlinkFormatter(isTTY: false, termProgram: "iTerm.app")
        #expect(formatter.formatURL("https://example.com") == "https://example.com")
        #expect(formatter.formatFilePath("/Users/nick/src/main.swift") == "/Users/nick/src/main.swift")
        #expect(formatter.hyperlinkURLs(in: "See https://example.com") == "See https://example.com")
    }
}
