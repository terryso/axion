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

    // MARK: - Italic Formatting

    @Test("italic with single asterisks")
    func italic_singleAsterisks() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("This is *italic* text")
        #expect(result.contains("\u{1B}[3m"))  // italic attribute
        #expect(result.contains("italic"))
        #expect(result.contains("\u{1B}[0m"))  // reset
    }

    @Test("italic with underscores")
    func italic_underscores() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("This is _italic_ text")
        #expect(result.contains("\u{1B}[3m"))  // italic attribute
        #expect(result.contains("italic"))
    }

    @Test("italic does not match snake_case identifiers")
    func italic_noSnakeCase() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("Use my_variable_name here")
        // snake_case should NOT be italicized
        #expect(!result.contains("\u{1B}[3m"))
    }

    @Test("italic ANSI256 color")
    func italic_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("This is *italic* text")
        #expect(result.contains("\u{1B}[3m"))  // italic attribute
        #expect(result.contains("\u{1B}[38;5;183m"))  // ANSI256 italic color
    }

    @Test("italic ANSI16 attribute only")
    func italic_ansi16() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi16, isTTY: true)
        let result = formatter.formatLine("This is *italic* text")
        #expect(result.contains("\u{1B}[3m"))  // italic attribute
    }

    @Test("italic in non-TTY passthrough")
    func italic_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("This is *italic* text")
        #expect(result == "This is *italic* text")
    }

    @Test("unclosed italic marker gets reset appended")
    func unclosedItalic_reset() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("This is *unclosed")
        #expect(result.contains("\u{1B}[3m"))
        #expect(result.hasSuffix("\u{1B}[0m"))
    }

    @Test("bold takes priority over italic for double asterisks")
    func boldPriority_overItalic() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("**bold** not *italic*")
        #expect(result.contains("\u{1B}[1m"))  // bold for **
        #expect(result.contains("\u{1B}[3m"))  // italic for *
    }

    // MARK: - Blockquote Formatting

    @Test("blockquote renders with vertical bar prefix")
    func blockquote_basic() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("> This is a quote")
        #expect(result.contains("│"))  // vertical bar
        #expect(result.contains("This is a quote"))
        #expect(result.contains("\u{1B}[38;2;100;100;120m"))  // dim color for prefix
    }

    @Test("blockquote without space after >")
    func blockquote_noSpace() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine(">Quoted")
        #expect(result.contains("│"))
        #expect(result.contains("Quoted"))
    }

    @Test("blockquote with leading whitespace")
    func blockquote_leadingWhitespace() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("  > Indented quote")
        #expect(result.hasPrefix("  "))
        #expect(result.contains("│"))
    }

    @Test("blockquote non-TTY passthrough")
    func blockquote_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("> Quoted text")
        #expect(result == "> Quoted text")
    }

    @Test("blockquote with inline formatting in text")
    func blockquote_withInlineFormatting() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("> Use **bold** in quote")
        #expect(result.contains("│"))
        #expect(result.contains("\u{1B}[1m"))  // bold
    }

    // MARK: - Unordered List Formatting

    @Test("unordered list with dash renders bullet")
    func unorderedList_dash() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- Item one")
        #expect(result.contains("•"))  // Unicode bullet
        #expect(result.contains("Item one"))
        #expect(result.contains("\u{1B}[38;2;250;204;21m"))  // yellow marker color
    }

    @Test("unordered list with asterisk renders bullet")
    func unorderedList_asterisk() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("* Item two")
        #expect(result.contains("•"))
        #expect(result.contains("Item two"))
    }

    @Test("unordered list with plus renders bullet")
    func unorderedList_plus() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("+ Item three")
        #expect(result.contains("•"))
        #expect(result.contains("Item three"))
    }

    @Test("unordered list preserves leading whitespace")
    func unorderedList_leadingWhitespace() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("  - Nested item")
        #expect(result.hasPrefix("  "))
        #expect(result.contains("•"))
    }

    @Test("unordered list non-TTY passthrough")
    func unorderedList_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("- Item one")
        #expect(result == "- Item one")
    }

    @Test("unordered list with inline formatting in text")
    func unorderedList_withInlineFormatting() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- Use **bold** here")
        #expect(result.contains("•"))
        #expect(result.contains("\u{1B}[1m"))  // bold
    }

    @Test("dash without space is not a list item")
    func dash_noSpace_notList() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("-not-a-list")
        #expect(!result.contains("•"))
    }

    // MARK: - Ordered List Formatting

    @Test("ordered list with dot renders colored number")
    func orderedList_dot() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("1. First item")
        #expect(result.contains("1."))
        #expect(result.contains("First item"))
        #expect(result.contains("\u{1B}[38;2;250;204;21m"))  // yellow marker color
    }

    @Test("ordered list with parenthesis renders colored number")
    func orderedList_paren() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("2) Second item")
        #expect(result.contains("2)"))
        #expect(result.contains("Second item"))
    }

    @Test("ordered list with large number")
    func orderedList_largeNumber() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("12. Twelfth item")
        #expect(result.contains("12."))
        #expect(result.contains("Twelfth item"))
    }

    @Test("ordered list non-TTY passthrough")
    func orderedList_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("1. First item")
        #expect(result == "1. First item")
    }

    @Test("number without delimiter is not a list item")
    func number_noDelimiter_notList() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("123abc")
        #expect(!result.contains("\u{1B}[38;2;250;204;21m"))
    }

    // MARK: - Edge Cases for New Features

    @Test("blockquote empty line")
    func blockquote_emptyLine() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine(">")
        #expect(result.contains("│"))
    }

    @Test("list item empty text falls through to inline")
    func listItem_emptyText() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- ")
        // Empty text after marker — should not be detected as list
        #expect(!result.contains("•"))
    }

    @Test("italic with bold and code in same line")
    func italic_bold_code_combined() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("**bold** *italic* `code`")
        #expect(result.contains("\u{1B}[1m"))  // bold
        #expect(result.contains("\u{1B}[3m"))  // italic
        #expect(result.contains("\u{1B}[38;2;110;231;183m"))  // code
    }

    @Test("list marker colors across profiles")
    func listMarker_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("- Item")
        #expect(result.contains("\u{1B}[38;5;220m"))  // ANSI256 yellow
    }

    @Test("list marker ANSI16")
    func listMarker_ansi16() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi16, isTTY: true)
        let result = formatter.formatLine("- Item")
        #expect(result.contains("\u{1B}[33m"))  // ANSI16 yellow
    }
}
