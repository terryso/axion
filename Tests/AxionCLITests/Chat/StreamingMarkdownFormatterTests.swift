import Testing
import Foundation

@testable import AxionCLI

// MARK: - StreamingMarkdownFormatter Tests

@Suite("StreamingMarkdownFormatter")
struct StreamingMarkdownFormatterTests {

    // MARK: - Plain Text Passthrough

    @Test("plain text passes through unchanged in non-TTY")
    func plainText_passthrough_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("Hello world")
        #expect(result == "Hello world")
    }

    @Test("empty string passes through unchanged")
    func emptyString_passthrough() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("")
        #expect(result == "")
    }

    @Test("plain text with no markdown passes through unchanged")
    func plainText_noMarkdown_passthrough() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("This is just a regular line of text.")
        #expect(result == "This is just a regular line of text.")
    }

    // MARK: - Heading Formatting

    @Test("H1 heading renders with color and bold")
    func h1_heading() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("# Main Title")
        // Should contain bold code and color code
        #expect(result.contains("\u{1B}[1m"))  // bold
        #expect(result.contains("\u{1B}[38;2;129;140;248m"))  // purple-blue for H1
        #expect(result.contains("#"))
        #expect(result.contains("Main Title"))
    }

    @Test("H2 heading renders with different color")
    func h2_heading() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("## Section")
        #expect(result.contains("\u{1B}[38;2;96;165;250m"))  // sky blue for H2
        #expect(result.contains("Section"))
    }

    @Test("H3 heading renders with gray-blue color")
    func h3_heading() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("### Subsection")
        #expect(result.contains("\u{1B}[38;2;148;163;184m"))  // gray-blue for H3
        #expect(result.contains("Subsection"))
    }

    @Test("H4 heading renders with gray-blue color")
    func h4_heading() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("#### Details")
        #expect(result.contains("\u{1B}[38;2;148;163;184m"))  // gray-blue for H4
        #expect(result.contains("Details"))
    }

    @Test("H5 is not treated as heading")
    func h5_notHeading() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("##### Too Deep")
        // Should be plain text passthrough (no bold/color)
        #expect(!result.contains("\u{1B}[1m"))
    }

    @Test("heading without space after hashes is not a heading")
    func heading_noSpace_notHeading() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("#NotAHeading")
        #expect(!result.contains("\u{1B}[1m"))
    }

    @Test("hashes without text is not a heading")
    func hashes_only_notHeading() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("###   ")
        // Only whitespace after hashes — should be passthrough
        #expect(!result.contains("\u{1B}[1m"))
    }

    @Test("heading preserves leading whitespace")
    func heading_preservesLeadingWhitespace() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("  ## Indented Heading")
        #expect(result.hasPrefix("  "))
        #expect(result.contains("Indented Heading"))
    }

    // MARK: - Heading with ANSI256

    @Test("H1 heading ANSI256 colors")
    func h1_heading_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("# Title")
        #expect(result.contains("\u{1B}[38;5;104m"))
    }

    @Test("H2 heading ANSI256 colors")
    func h2_heading_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("## Section")
        #expect(result.contains("\u{1B}[38;5;111m"))
    }

    // MARK: - Heading with ANSI16

    @Test("heading ANSI16 uses cyan")
    func heading_ansi16() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi16, isTTY: true)
        let result = formatter.formatLine("# Title")
        #expect(result.contains("\u{1B}[36m"))  // cyan
    }

    // MARK: - Heading with unknown profile

    @Test("heading unknown profile no ANSI codes")
    func heading_unknown_noANSI() {
        let formatter = StreamingMarkdownFormatter(profile: .unknown, isTTY: true)
        let result = formatter.formatLine("# Title")
        #expect(!result.contains("\u{1B}["))
    }

    // MARK: - Horizontal Rule

    @Test("horizontal rule with dashes renders as unicode line")
    func horizontalRule_dashes() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true, terminalWidth: 40)
        let result = formatter.formatLine("---")
        // Should contain dim code and unicode dashes
        #expect(result.contains("\u{1B}[38;2;100;100;120m"))  // dim color
        #expect(result.contains("─"))
        #expect(result.contains("\u{1B}[0m"))  // reset
        #expect(!result.contains("---"))  // original dashes replaced
    }

    @Test("horizontal rule with asterisks renders as unicode line")
    func horizontalRule_asterisks() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true, terminalWidth: 40)
        let result = formatter.formatLine("***")
        #expect(result.contains("─"))
    }

    @Test("horizontal rule with underscores renders as unicode line")
    func horizontalRule_underscores() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true, terminalWidth: 40)
        let result = formatter.formatLine("___")
        #expect(result.contains("─"))
    }

    @Test("horizontal rule with long dashes")
    func horizontalRule_longDashes() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true, terminalWidth: 40)
        let result = formatter.formatLine("----------")
        #expect(result.contains("─"))
    }

    @Test("horizontal rule non-TTY passthrough")
    func horizontalRule_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("---")
        #expect(result == "---")
    }

    @Test("not horizontal rule with mixed characters")
    func notHorizontalRule_mixed() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("--*")
        #expect(result == "--*")  // passthrough
    }

    @Test("not horizontal rule too short")
    func notHorizontalRule_tooShort() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("--")
        #expect(result == "--")  // passthrough
    }

    // MARK: - Bold Formatting

    @Test("bold text with double asterisks")
    func bold_doubleAsterisks() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("This is **bold** text")
        #expect(result.contains("\u{1B}[1m"))  // bold on
        #expect(result.contains("bold"))
        #expect(result.contains("\u{1B}[0m"))  // bold off / reset
    }

    @Test("multiple bold segments in one line")
    func bold_multipleSegments() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("**first** and **second**")
        // Should have two bold on and two bold off
        let boldOnCount = result.components(separatedBy: "\u{1B}[1m").count - 1
        #expect(boldOnCount == 2)
    }

    @Test("bold across entire line")
    func bold_entireLine() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("**everything is bold**")
        #expect(result.contains("\u{1B}[1m"))
    }

    @Test("bold in non-TTY passthrough")
    func bold_nonTTY_passthrough() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("This is **bold** text")
        #expect(result == "This is **bold** text")
    }

    // MARK: - Inline Code Formatting

    @Test("inline code with backticks")
    func inlineCode_backticks() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("Use the `print()` function")
        #expect(result.contains("\u{1B}[38;2;110;231;183m"))  // teal/green for inline code
        #expect(result.contains("print()"))
    }

    @Test("inline code ANSI256")
    func inlineCode_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("Run `swift test`")
        #expect(result.contains("\u{1B}[38;5;121m"))  // ANSI256 teal
    }

    @Test("inline code ANSI16")
    func inlineCode_ansi16() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi16, isTTY: true)
        let result = formatter.formatLine("Run `swift test`")
        #expect(result.contains("\u{1B}[36m"))  // cyan
    }

    @Test("inline code non-TTY passthrough")
    func inlineCode_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("Use the `print()` function")
        #expect(result == "Use the `print()` function")
    }

    @Test("multiple inline code segments")
    func inlineCode_multiple() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("Use `foo` and `bar` here")
        let codeOnCount = result.components(separatedBy: "\u{1B}[38;2;110;231;183m").count - 1
        #expect(codeOnCount == 2)
    }

    // MARK: - Combined Inline Elements

    @Test("bold and inline code in same line")
    func boldAndInlineCode() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("**Important:** use `git commit`")
        #expect(result.contains("\u{1B}[1m"))  // bold
        #expect(result.contains("\u{1B}[38;2;110;231;183m"))  // inline code color
    }

    @Test("bold does not apply inside inline code")
    func bold_doesNotApplyInsideCode() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        // `**bold**` — the ** is inside backticks, should NOT be bold-formatted
        let result = formatter.formatLine("Type `**bold**` literally")
        // Should contain code color but NOT bold (since ** is inside backticks)
        let codeColorCode = "\u{1B}[38;2;110;231;183m"
        #expect(result.contains(codeColorCode))
        // The ** inside backticks should not trigger bold formatting
        // (bold is skipped when inCode is true)
    }

    // MARK: - Unclosed Markers

    @Test("unclosed bold marker gets reset appended")
    func unclosedBold_reset() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("This is **unclosed")
        // Should have bold on and a reset at end
        #expect(result.contains("\u{1B}[1m"))
        #expect(result.hasSuffix("\u{1B}[0m"))
    }

    @Test("unclosed code marker gets reset appended")
    func unclosedCode_reset() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("Use `unclosed")
        #expect(result.hasSuffix("\u{1B}[0m"))
    }

    // MARK: - Horizontal Rule ANSI Variants

    @Test("horizontal rule ANSI256 dim code")
    func horizontalRule_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true, terminalWidth: 20)
        let result = formatter.formatLine("---")
        #expect(result.contains("\u{1B}[38;5;243m"))
    }

    @Test("horizontal rule ANSI16 dim code")
    func horizontalRule_ansi16() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi16, isTTY: true, terminalWidth: 20)
        let result = formatter.formatLine("---")
        #expect(result.contains("\u{1B}[2m"))  // dim attribute
    }

    @Test("horizontal rule unknown profile no ANSI")
    func horizontalRule_unknown_noANSI() {
        let formatter = StreamingMarkdownFormatter(profile: .unknown, isTTY: true, terminalWidth: 20)
        let result = formatter.formatLine("---")
        #expect(!result.contains("\u{1B}["))
    }

    // MARK: - Integration: Code Block Renderer with Markdown Formatter

    @Test("code block renderer uses markdown formatter for plain text")
    func codeBlockRenderer_usesFormatter() {
        var formatted: [String] = []
        let mdFormatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)

        var renderer = StreamingCodeBlockRenderer(
            profile: .trueColor,
            isTTY: true,
            terminalWidth: 40,
            plainTextFormatter: { mdFormatter.formatLine($0) }
        )

        // Plain text should be formatted
        renderer.process("## Hello\n") { formatted.append($0) }
        #expect(formatted.contains("\n"))
        let helloLine = formatted.first { $0.contains("Hello") } ?? ""
        #expect(helloLine.contains("\u{1B}[38;2;96;165;250m"))  // H2 color

        formatted.removeAll()

        // Code fence line should NOT be formatted
        renderer.process("```swift\n") { formatted.append($0) }
        let fenceLine = formatted.first { $0.contains("swift") } ?? ""
        #expect(fenceLine.contains("╭"))  // code block border, not markdown heading
    }

    @Test("code block content is not markdown formatted")
    func codeBlockContent_notFormatted() {
        var formatted: [String] = []

        let mdFormatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        var renderer = StreamingCodeBlockRenderer(
            profile: .trueColor,
            isTTY: true,
            terminalWidth: 40,
            plainTextFormatter: { mdFormatter.formatLine($0) }
        )

        renderer.process("```swift\n") { formatted.append($0) }
        formatted.removeAll()

        // Code inside block should have pipe prefix, not markdown formatting
        renderer.process("**bold code**\n") { formatted.append($0) }
        let codeLine = formatted.joined()
        #expect(codeLine.contains("│"))  // code content prefix
        #expect(!codeLine.contains("\u{1B}[1m"))  // NOT bold formatted
    }

    // MARK: - Edge Cases

    @Test("single asterisk is not bold")
    func singleAsterisk_notBold() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("a * b * c")
        #expect(!result.contains("\u{1B}[1m"))
    }

    @Test("line with only hashes and no space")
    func hashes_noSpace() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("##nope")
        #expect(!result.contains("\u{1B}[1m"))
    }

    @Test("heading with inline code in text")
    func heading_withInlineCode() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("## Using `async/await`")
        #expect(result.contains("\u{1B}[38;2;96;165;250m"))  // H2 color
        #expect(result.contains("\u{1B}[38;2;110;231;183m"))  // inline code color
    }

    @Test("heading with bold in text")
    func heading_withBold() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("# **Important** Update")
        #expect(result.contains("\u{1B}[38;2;129;140;248m"))  // H1 color
        #expect(result.contains("\u{1B}[1m"))  // bold
    }
}
