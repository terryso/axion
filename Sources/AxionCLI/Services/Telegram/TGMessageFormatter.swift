import Foundation

enum TGMessageFormatter {

    // MARK: - Escape Utilities

    static let mdV2SpecialChars: Set<Character> = [
        "_", "*", "[", "]", "(", ")", "~", "`", ">", "#", "+", "-", "=", "|", "{", "}", ".", "!", "\\"
    ]

    static func escapeMarkdownV2(_ text: String) -> String {
        var result = String()
        result.reserveCapacity(text.count * 2)
        for char in text {
            if mdV2SpecialChars.contains(char) {
                result.append("\\")
            }
            result.append(char)
        }
        return result
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func stripANSIEscapeCodes(_ text: String) -> String {
        let pattern = "\u{001B}\\[[0-9;]*[A-Za-z]"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    // MARK: - Public Format API

    static func format(_ text: String) -> (String, TGParseMode) {
        let cleaned = stripANSIEscapeCodes(text)
        let formatted = renderMarkdownV2(cleaned)
        return (formatted, .markdownV2)
    }

    static func formatAsHTML(_ text: String) -> (String, TGParseMode) {
        let cleaned = stripANSIEscapeCodes(text)
        let formatted = renderHTML(cleaned)
        return (formatted, .html)
    }

    static func formatAsPlain(_ text: String) -> (String, TGParseMode) {
        let cleaned = stripANSIEscapeCodes(text)
        let formatted = renderPlain(cleaned)
        return (formatted, .plain)
    }

    // MARK: - Split

    static func split(formattedText: String, parseMode: TGParseMode, maxRenderedLength: Int = 4096) -> [String] {
        guard formattedText.utf8.count > maxRenderedLength else { return [formattedText] }

        var chunks: [String] = []
        var remaining = formattedText[...]

        while !remaining.isEmpty {
            if remaining.utf8.count <= maxRenderedLength {
                chunks.append(String(remaining))
                break
            }

            // Walk from max UTF-8 offset backwards to find a valid String.Index
            let utf8Start = remaining.utf8.startIndex
            let utf8Target = remaining.utf8.index(utf8Start, offsetBy: maxRenderedLength)
            let cutIndex = remaining.index(utf8Target, offsetBy: 0) // clamps to nearest Character boundary
            let searchRange = remaining[..<cutIndex]

            // Try to split at paragraph boundary (double newline)
            if let paraBreak = searchRange.range(of: "\n\n", options: .backwards) {
                // Check that this doesn't split inside a code block
                let beforeBreak = String(remaining[..<paraBreak.lowerBound])
                if !isInsideCodeBlock(at: beforeBreak) {
                    chunks.append(beforeBreak)
                    remaining = remaining[paraBreak.upperBound...]
                    continue
                }
            }

            // Try single newline
            if let newline = searchRange.range(of: "\n", options: .backwards) {
                // Check that this doesn't split inside a code block
                let beforeNewline = String(remaining[..<newline.lowerBound])
                if !isInsideCodeBlock(at: beforeNewline) {
                    chunks.append(beforeNewline)
                    remaining = remaining[newline.upperBound...]
                    continue
                }
            }

            // Hard split at max length
            chunks.append(String(remaining[..<cutIndex]))
            remaining = remaining[cutIndex...]
        }

        // Ensure each chunk is independently renderable (balance code blocks)
        return balanceCodeBlocks(chunks)
    }

    /// Returns true if the text ends inside a code block (odd number of ``` fences).
    private static func isInsideCodeBlock(at text: String) -> Bool {
        let fenceCount = text.components(separatedBy: "```").count - 1
        return fenceCount % 2 != 0
    }

    private static func balanceCodeBlocks(_ chunks: [String]) -> [String] {
        var result: [String] = []
        var insideCodeBlock = false

        for chunk in chunks {
            var current = chunk

            if insideCodeBlock {
                // This chunk continues a code block — prepend opening fence
                current = "```\n" + current
            }

            // Count net fence state after potential prepend
            let adjustedFenceCount = current.components(separatedBy: "```").count - 1
            if adjustedFenceCount % 2 != 0 {
                // Odd number — unclosed code block at end of chunk
                if !current.hasSuffix("\n") { current += "\n" }
                current += "```"
                insideCodeBlock = true
            } else {
                insideCodeBlock = false
            }

            result.append(current)
        }

        return result
    }

    // MARK: - Parsing Helpers

    struct ListContent {
        let indent: Int
        let text: String
    }

    struct OrderedListContent {
        let indent: Int
        let number: Int
        let text: String
    }

    static func parseHeading(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var hashCount = 0
        for char in trimmed {
            if char == "#" { hashCount += 1 } else { break }
        }
        guard hashCount > 0, hashCount <= 6 else { return nil }
        let content = String(trimmed.dropFirst(hashCount)).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return content
    }

    static func parseBlockQuote(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else { return nil }
        let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return content
    }

    static func parseUnorderedList(_ line: String) -> ListContent? {
        let trimmed = line // preserve leading spaces for indent calculation
        var spaces = 0
        for char in trimmed {
            if char == " " { spaces += 1 } else { break }
        }
        let indent = spaces / 2
        let afterSpaces = String(trimmed.dropFirst(spaces))
        if afterSpaces.hasPrefix("- ") || afterSpaces.hasPrefix("* ") {
            return ListContent(indent: indent, text: String(afterSpaces.dropFirst(2)))
        }
        return nil
    }

    static func parseOrderedList(_ line: String) -> OrderedListContent? {
        var spaces = 0
        for char in line {
            if char == " " { spaces += 1 } else { break }
        }
        let indent = spaces / 2
        let afterSpaces = String(line.dropFirst(spaces))

        // Match: 1. text
        let pattern = /^(\d+)\.\s(.+)/
        guard let match = afterSpaces.firstMatch(of: pattern),
              let number = Int(match.1) else { return nil }
        return OrderedListContent(indent: indent, number: number, text: String(match.2))
    }

    // MARK: - Regex Helpers

    static func replacePattern(_ text: String, pattern: String, handler: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let captured = String(text[range])
            let fullRange = Range(match.range, in: text)!
            result.replaceSubrange(fullRange, with: handler(captured))
        }
        return result
    }

    static func replacePattern(_ text: String, pattern: String, handler: (String, String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        var result = text
        for match in matches.reversed() {
            guard let range1 = Range(match.range(at: 1), in: text),
                  let range2 = Range(match.range(at: 2), in: text) else { continue }
            let captured1 = String(text[range1])
            let captured2 = String(text[range2])
            let fullRange = Range(match.range, in: text)!
            result.replaceSubrange(fullRange, with: handler(captured1, captured2))
        }
        return result
    }
}
