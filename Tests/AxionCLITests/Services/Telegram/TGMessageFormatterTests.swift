import Testing
import Foundation
@testable import AxionCLI

@Suite("TGMessageFormatter")
struct TGMessageFormatterTests {

    // MARK: - MarkdownV2 Formatting

    @Test("Format heading")
    func formatHeading() {
        let (result, mode) = TGMessageFormatter.format("# Title")
        #expect(mode == .markdownV2)
        #expect(result == "**Title**")
    }

    @Test("Format h2 heading")
    func formatH2Heading() {
        let (result, _) = TGMessageFormatter.format("## Section Title")
        #expect(result == "**Section Title**")
    }

    @Test("Format unordered list")
    func formatUnorderedList() {
        let (result, _) = TGMessageFormatter.format("- first item\n- second item")
        #expect(result.contains("• first item"))
        #expect(result.contains("• second item"))
    }

    @Test("Format ordered list")
    func formatOrderedList() {
        let (result, _) = TGMessageFormatter.format("1. first\n2. second")
        #expect(result.contains("1\\. first"))
        #expect(result.contains("2\\. second"))
    }

    @Test("Format code block preserves content")
    func formatCodeBlock() {
        let input = "```swift\nprint(\"hello.world\")\n```"
        let (result, _) = TGMessageFormatter.format(input)
        #expect(result.contains("```swift"))
        #expect(result.contains("print(\"hello.world\")"))
        #expect(result.hasSuffix("```"))
    }

    @Test("Format inline code")
    func formatInlineCode() {
        let (result, _) = TGMessageFormatter.format("Use `code.here` to do stuff")
        #expect(result.contains("`code.here`"))
    }

    @Test("Format link")
    func formatLink() {
        let (result, _) = TGMessageFormatter.format("[Google](https://google.com)")
        // Label and URL are both escaped in MarkdownV2
        #expect(result.contains("Google"))
        #expect(result.contains("google"))
        // Link brackets/parens are NOT escaped — they form the link syntax
        #expect(!result.contains("\\[Google\\]"))
        #expect(!result.contains("\\](\\"))
    }

    @Test("Format table degrades to key/value")
    func formatTableDegrades() {
        let (result, _) = TGMessageFormatter.format("| Name | Value |\n|------|-------|\n| Key1 | Val1 |")
        #expect(result.contains("Name"))
        #expect(result.contains("Val1"))
        // Separator row should be empty
        #expect(!result.contains("------"))
    }

    @Test("MarkdownV2 escapes special characters in text")
    func escapeSpecialChars() {
        let (result, _) = TGMessageFormatter.format("hello.world")
        #expect(result == "hello\\.world")
    }

    @Test("MarkdownV2 escapes dash")
    func escapeDash() {
        let (result, _) = TGMessageFormatter.format("test-case")
        #expect(result == "test\\-case")
    }

    @Test("MarkdownV2 does not escape inside code blocks")
    func noEscapeInCodeBlocks() {
        let input = "```js\nobj.key = true;\n```"
        let (result, _) = TGMessageFormatter.format(input)
        #expect(result.contains("obj.key = true;"))
        #expect(!result.contains("obj\\.key"))
    }

    // MARK: - HTML Formatting

    @Test("HTML format heading uses bold tag")
    func htmlFormatHeading() {
        let (result, mode) = TGMessageFormatter.formatAsHTML("# Title")
        #expect(mode == .html)
        #expect(result == "<b>Title</b>")
    }

    @Test("HTML format code block")
    func htmlFormatCodeBlock() {
        let input = "```python\nx = 1\n```"
        let (result, _) = TGMessageFormatter.formatAsHTML(input)
        #expect(result.contains("<pre><code>"))
        #expect(result.contains("x = 1"))
        #expect(result.contains("</code></pre>"))
    }

    @Test("HTML format inline code produces valid tags")
    func htmlFormatInlineCode() {
        let (result, _) = TGMessageFormatter.formatAsHTML("Use `code` here")
        #expect(result.contains("<code>code</code>"))
        #expect(!result.contains("&lt;code&gt;"))
    }

    @Test("HTML format bold produces valid tags")
    func htmlFormatBold() {
        let (result, _) = TGMessageFormatter.formatAsHTML("This is **bold** text")
        #expect(result.contains("<b>bold</b>"))
        #expect(!result.contains("&lt;b&gt;"))
    }

    @Test("HTML format link produces valid anchor tag")
    func htmlFormatLink() {
        let (result, _) = TGMessageFormatter.formatAsHTML("[Click](https://example.com)")
        #expect(result.contains("<a href=\"https://example.com\">Click</a>"))
        #expect(!result.contains("&lt;a"))
    }

    @Test("HTML escapes ampersands in regular text")
    func htmlEscapesAmpersands() {
        let (result, _) = TGMessageFormatter.formatAsHTML("a & b")
        #expect(result.contains("&amp;"))
    }

    // MARK: - Plain Formatting

    @Test("Plain format heading uppercases")
    func plainFormatHeading() {
        let (result, mode) = TGMessageFormatter.formatAsPlain("# Title")
        #expect(mode == .plain)
        #expect(result == "TITLE")
    }

    @Test("Plain format strips bold markers")
    func plainFormatStripsBold() {
        let (result, _) = TGMessageFormatter.formatAsPlain("This is **bold** text")
        #expect(result == "This is bold text")
    }

    @Test("Plain format link shows label:url")
    func plainFormatLink() {
        let (result, _) = TGMessageFormatter.formatAsPlain("[Click here](https://example.com)")
        #expect(result == "Click here: https://example.com")
    }

    // MARK: - Split

    @Test("Short text is not split")
    func shortTextNotSplit() {
        let chunks = TGMessageFormatter.split(formattedText: "short text", parseMode: .markdownV2)
        #expect(chunks.count == 1)
        #expect(chunks[0] == "short text")
    }

    @Test("Long text splits at paragraph boundary")
    func splitAtParagraphBoundary() {
        let para1 = String(repeating: "A", count: 3000)
        let para2 = String(repeating: "B", count: 2000)
        let text = "\(para1)\n\n\(para2)"
        let chunks = TGMessageFormatter.split(formattedText: text, parseMode: .plain)
        #expect(chunks.count == 2)
        #expect(chunks[0].count <= 4096)
    }

    @Test("Long text splits at newline if no paragraph break")
    func splitAtNewline() {
        let line1 = String(repeating: "X", count: 3000)
        let line2 = String(repeating: "Y", count: 2000)
        let text = "\(line1)\n\(line2)"
        let chunks = TGMessageFormatter.split(formattedText: text, parseMode: .plain)
        #expect(chunks.count == 2)
    }

    @Test("Each chunk is independently renderable — balances code blocks")
    func splitBalancesCodeBlocks() {
        let code = String(repeating: "line\n", count: 1000)
        let text = "```\n\(code)```"
        let chunks = TGMessageFormatter.split(formattedText: text, parseMode: .markdownV2, maxRenderedLength: 2000)
        // Every chunk should have balanced code fences
        for chunk in chunks {
            let fenceCount = chunk.components(separatedBy: "```").count - 1
            #expect(fenceCount % 2 == 0, "Unbalanced code block in chunk: \(chunk.prefix(50))")
        }
    }

    @Test("Exactly max length is not split")
    func exactlyMaxLengthNotSplit() {
        let text = String(repeating: "A", count: 4096)
        let chunks = TGMessageFormatter.split(formattedText: text, parseMode: .plain)
        #expect(chunks.count == 1)
    }
}
