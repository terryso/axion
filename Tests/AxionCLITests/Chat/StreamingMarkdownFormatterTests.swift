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

    // MARK: - Task List Formatting

    @Test("task list unchecked renders empty checkbox")
    func taskList_unchecked() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- [ ] Pending task")
        #expect(result.contains("☐"))  // empty checkbox
        #expect(result.contains("Pending task"))
        // Should use dim gray color for unchecked
        #expect(result.contains("\u{1B}[38;2;120;120;140m"))
    }

    @Test("task list checked renders checked checkbox")
    func taskList_checked() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- [x] Done task")
        #expect(result.contains("☑"))  // checked checkbox
        #expect(result.contains("Done task"))
        // Should use green color for checked
        #expect(result.contains("\u{1B}[38;2;76;175;80m"))
    }

    @Test("task list checked with capital X")
    func taskList_capitalX() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- [X] Capital X")
        #expect(result.contains("☑"))
        #expect(result.contains("Capital X"))
    }

    @Test("task list with asterisk marker")
    func taskList_asteriskMarker() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("* [ ] Asterisk task")
        #expect(result.contains("☐"))
        #expect(result.contains("Asterisk task"))
    }

    @Test("task list with plus marker")
    func taskList_plusMarker() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("+ [x] Plus task")
        #expect(result.contains("☑"))
        #expect(result.contains("Plus task"))
    }

    @Test("task list preserves leading whitespace")
    func taskList_leadingWhitespace() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("  - [ ] Nested task")
        #expect(result.hasPrefix("  "))
        #expect(result.contains("☐"))
    }

    @Test("task list with inline formatting in text")
    func taskList_withInlineFormatting() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- [x] Use **bold** in task")
        #expect(result.contains("☑"))
        #expect(result.contains("\u{1B}[1m"))  // bold
    }

    @Test("task list empty text")
    func taskList_emptyText() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- [ ]")
        #expect(result.contains("☐"))
    }

    @Test("task list non-TTY passthrough")
    func taskList_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("- [ ] Pending task")
        #expect(result == "- [ ] Pending task")
    }

    @Test("task list checked ANSI256 green")
    func taskList_checked_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("- [x] Done")
        #expect(result.contains("☑"))
        #expect(result.contains("\u{1B}[38;5;71m"))  // ANSI256 green
    }

    @Test("task list unchecked ANSI256 dim")
    func taskList_unchecked_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("- [ ] Pending")
        #expect(result.contains("☐"))
        #expect(result.contains("\u{1B}[38;5;244m"))  // ANSI256 dim gray
    }

    @Test("dash bracket but not task list")
    func dash_bracket_notTaskList() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- [invalid content")
        // Should NOT be a task list — bracket not followed by space/x/X]
        #expect(!result.contains("☐"))
        #expect(!result.contains("☑"))
    }

    // MARK: - Strikethrough Formatting

    @Test("strikethrough with double tilde")
    func strikethrough_basic() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("This is ~~deleted~~ text")
        #expect(result.contains("\u{1B}[9m"))  // strikethrough attribute
        #expect(result.contains("deleted"))
        #expect(result.contains("\u{1B}[0m"))  // reset
    }

    @Test("strikethrough TrueColor has dim red color")
    func strikethrough_trueColor() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("~~old text~~")
        #expect(result.contains("\u{1B}[9m"))  // strikethrough
        #expect(result.contains("\u{1B}[38;2;140;120;120m"))  // dim red-gray
    }

    @Test("strikethrough ANSI256")
    func strikethrough_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("~~deleted~~")
        #expect(result.contains("\u{1B}[9m"))
        #expect(result.contains("\u{1B}[38;5;138m"))
    }

    @Test("strikethrough ANSI16")
    func strikethrough_ansi16() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi16, isTTY: true)
        let result = formatter.formatLine("~~deleted~~")
        #expect(result.contains("\u{1B}[9m"))  // strikethrough
        #expect(result.contains("\u{1B}[2m"))  // dim
    }

    @Test("strikethrough non-TTY passthrough")
    func strikethrough_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("This is ~~deleted~~ text")
        #expect(result == "This is ~~deleted~~ text")
    }

    @Test("strikethrough unclosed gets reset")
    func strikethrough_unclosed_reset() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("This is ~~unclosed")
        #expect(result.contains("\u{1B}[9m"))
        #expect(result.hasSuffix("\u{1B}[0m"))
    }

    @Test("single tilde is not strikethrough")
    func singleTilde_notStrikethrough() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("a ~ b")
        #expect(!result.contains("\u{1B}[9m"))
    }

    @Test("strikethrough with bold in same line")
    func strikethrough_withBold() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("**bold** and ~~strikethrough~~")
        #expect(result.contains("\u{1B}[1m"))  // bold
        #expect(result.contains("\u{1B}[9m"))  // strikethrough
    }

    // MARK: - Inline Link Formatting

    @Test("inline link renders colored text without OSC 8")
    func inlineLink_noOSC8() {
        // No hyperlinkFormatter → text + dim URL
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("Visit [docs](https://example.com) here")
        #expect(result.contains("\u{1B}[38;2;96;165;250m"))  // link color (sky blue)
        #expect(result.contains("docs"))
        #expect(result.contains("(https://example.com)"))  // dim URL shown
    }

    @Test("inline link with OSC 8 support")
    func inlineLink_withOSC8() {
        let hyperlinkFormatter = TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        let formatter = StreamingMarkdownFormatter(
            profile: .trueColor,
            isTTY: true,
            hyperlinkFormatter: hyperlinkFormatter
        )
        let result = formatter.formatLine("Visit [docs](https://example.com) here")
        #expect(result.contains("docs"))
        // OSC 8 sequence: ESC]8;;urlBEL
        #expect(result.contains("\u{1B}]8;;https://example.com\u{07}"))
    }

    @Test("inline link non-TTY passthrough")
    func inlineLink_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("Visit [docs](https://example.com) here")
        #expect(result == "Visit [docs](https://example.com) here")
    }

    @Test("inline link empty text not treated as link")
    func inlineLink_emptyText() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("[](https://example.com)")
        // Empty link text → not a valid link, should passthrough
        #expect(!result.contains("\u{1B}[38;2;96;165;250m"))
    }

    @Test("inline link empty URL not treated as link")
    func inlineLink_emptyURL() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("[text]()")
        // Empty URL → not a valid link
        #expect(!result.contains("\u{1B}[38;2;96;165;250m"))
    }

    @Test("inline link with bold in text")
    func inlineLink_boldInText() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        // Links are parsed before bold/italic, so ** inside [] won't trigger bold
        let result = formatter.formatLine("[**bold link**](https://example.com)")
        #expect(result.contains("\u{1B}[38;2;96;165;250m"))  // link color
    }

    @Test("multiple inline links in same line")
    func inlineLink_multiple() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("[foo](http://a.com) and [bar](http://b.com)")
        let linkColorCount = result.components(separatedBy: "\u{1B}[38;2;96;165;250m").count - 1
        #expect(linkColorCount == 2)
    }

    @Test("link URL with parentheses")
    func inlineLink_urlWithParens() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("[wiki](https://en.wikipedia.org/wiki/Page_(disambiguation))")
        #expect(result.contains("\u{1B}[38;2;96;165;250m"))  // link color
        #expect(result.contains("wiki"))
    }

    @Test("bracket without paren is not a link")
    func bracketWithoutParen_notLink() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("See [README] for details")
        // No (url) after ] → not a link
        #expect(!result.contains("\u{1B}[38;2;96;165;250m"))
    }

    @Test("inline link ANSI256 color")
    func inlineLink_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("[docs](https://example.com)")
        #expect(result.contains("\u{1B}[38;5;111m"))  // ANSI256 sky blue
    }

    @Test("inline link ANSI16 color")
    func inlineLink_ansi16() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi16, isTTY: true)
        let result = formatter.formatLine("[docs](https://example.com)")
        #expect(result.contains("\u{1B}[34m"))  // ANSI16 blue
    }

    // MARK: - Combined New Features

    @Test("task list with strikethrough in text")
    func taskList_withStrikethrough() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- [x] ~~old approach~~ replaced")
        #expect(result.contains("☑"))
        #expect(result.contains("\u{1B}[9m"))  // strikethrough
    }

    @Test("link in list item")
    func linkInListItem() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("- See [docs](https://example.com)")
        #expect(result.contains("•"))  // bullet
        #expect(result.contains("\u{1B}[38;2;96;165;250m"))  // link color
    }

    @Test("strikethrough with inline code")
    func strikethrough_withInlineCode() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("~~old `code` style~~")
        #expect(result.contains("\u{1B}[9m"))  // strikethrough
    }

    // MARK: - Heading Underline Decoration

    @Test("H1 heading includes double-line underline")
    func h1_heading_hasUnderline() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("# Title")
        // Should contain newline separating heading from underline
        #expect(result.contains("\n"))
        // Underline should use ═ characters (double line for H1)
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[1].contains("═"))
    }

    @Test("H2 heading includes single-line underline")
    func h2_heading_hasUnderline() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("## Section")
        #expect(result.contains("\n"))
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[1].contains("─"))
    }

    @Test("H3 heading has no underline")
    func h3_heading_noUnderline() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("### Subsection")
        // H3 should NOT have an underline (single line output)
        #expect(!result.contains("\n"))
    }

    @Test("H4 heading has no underline")
    func h4_heading_noUnderline() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("#### Details")
        #expect(!result.contains("\n"))
    }

    @Test("H1 underline width matches heading text")
    func h1_underlineWidth() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("# Hi")
        let lines = result.components(separatedBy: "\n")
        // Underline width = "# " (2) + "Hi" (2) = 4 ═ characters
        // Strip ANSI codes to get visible underline
        let underlineVisible = stripANSI(lines[1])
        #expect(underlineVisible == "════")
    }

    @Test("H2 underline width matches heading text")
    func h2_underlineWidth() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("## Hello World")
        let lines = result.components(separatedBy: "\n")
        // Underline width = "## " (3) + "Hello World" (11) = 14 ─ characters
        let underlineVisible = stripANSI(lines[1])
        #expect(underlineVisible == String(repeating: "─", count: 14))
    }

    @Test("H1 underline uses dim color")
    func h1_underline_dimColor() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("# Title")
        let lines = result.components(separatedBy: "\n")
        // Underline line should use dim color code
        #expect(lines[1].contains("\u{1B}[38;2;100;100;120m"))
    }

    @Test("H1 underline ANSI256 color")
    func h1_underline_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("# Title")
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[1].contains("\u{1B}[38;5;243m"))
    }

    @Test("H1 underline ANSI16 color")
    func h1_underline_ansi16() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi16, isTTY: true)
        let result = formatter.formatLine("# Title")
        let lines = result.components(separatedBy: "\n")
        #expect(lines.count == 2)
        #expect(lines[1].contains("\u{1B}[2m"))  // dim
    }

    @Test("H1 heading preserves leading spaces with underline")
    func h1_leadingSpaces_withUnderline() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("  # Indented")
        let lines = result.components(separatedBy: "\n")
        // First line should have leading spaces preserved
        #expect(lines[0].hasPrefix("  "))
        #expect(lines.count == 2)
        #expect(lines[1].contains("═"))
    }

    @Test("heading underline non-TTY passthrough")
    func heading_underline_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("# Title")
        // Non-TTY: no ANSI codes, no underline
        #expect(!result.contains("\u{1B}"))
        #expect(!result.contains("\n"))
    }

    // MARK: - Image Syntax

    @Test("image syntax renders as camera emoji placeholder")
    func image_basic() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("![screenshot](https://example.com/img.png)")
        #expect(result.contains("📷"))
        #expect(result.contains("screenshot"))
        #expect(result.contains("\u{1B}[38;2;96;165;250m"))  // link color
    }

    @Test("image syntax renders brackets around emoji")
    func image_hasBrackets() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("![diagram](https://example.com/diagram.png)")
        #expect(result.contains("[📷"))
        #expect(result.contains("]"))
    }

    @Test("image with empty alt text uses fallback")
    func image_emptyAlt() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("![](https://example.com/img.png)")
        #expect(result.contains("📷"))
        #expect(result.contains("image"))  // fallback text
    }

    @Test("image in text context")
    func image_inContext() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("Here is a ![photo](https://example.com/p.jpg) in text")
        #expect(result.contains("📷"))
        #expect(result.contains("photo"))
        #expect(result.contains("Here is a"))
        #expect(result.contains("in text"))
    }

    @Test("image with OSC 8 hyperlink")
    func image_osc8() {
        let formatter = StreamingMarkdownFormatter(
            profile: .trueColor,
            isTTY: true,
            hyperlinkFormatter: TerminalHyperlinkFormatter(isTTY: true, termProgram: "iTerm.app")
        )
        let result = formatter.formatLine("![icon](https://example.com/icon.svg)")
        // Should contain OSC 8 hyperlink escape sequence
        #expect(result.contains("\u{1B}]8;;"))
        #expect(result.contains("https://example.com/icon.svg"))
        #expect(result.contains("📷"))
    }

    @Test("image without OSC 8 does not show URL")
    func image_noOSC8_noURL() {
        let formatter = StreamingMarkdownFormatter(
            profile: .trueColor,
            isTTY: true,
            hyperlinkFormatter: TerminalHyperlinkFormatter(isTTY: true, termProgram: nil)
        )
        let result = formatter.formatLine("![icon](https://example.com/icon.svg)")
        // Without OSC 8, URL should not appear in visible output
        #expect(!result.contains("https://example.com/icon.svg"))
        #expect(result.contains("📷"))
    }

    @Test("image syntax non-TTY passthrough")
    func image_nonTTY() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: false)
        let result = formatter.formatLine("![alt](https://example.com/img.png)")
        // Non-TTY: passthrough unchanged
        #expect(result == "![alt](https://example.com/img.png)")
    }

    @Test("image ANSI256 color")
    func image_ansi256() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi256, isTTY: true)
        let result = formatter.formatLine("![pic](https://example.com/pic.png)")
        #expect(result.contains("\u{1B}[38;5;111m"))  // ANSI256 sky blue
        #expect(result.contains("📷"))
    }

    @Test("image ANSI16 color")
    func image_ansi16() {
        let formatter = StreamingMarkdownFormatter(profile: .ansi16, isTTY: true)
        let result = formatter.formatLine("![pic](https://example.com/pic.png)")
        #expect(result.contains("\u{1B}[34m"))  // ANSI16 blue
        #expect(result.contains("📷"))
    }

    @Test("exclamation mark without bracket is not image")
    func exclamationNotImage() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("Wow! That's great")
        #expect(!result.contains("📷"))
    }

    @Test("image and link in same line")
    func imageAndLink_sameLine() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("See ![img](https://a.com/i.png) and [link](https://b.com)")
        #expect(result.contains("📷"))
        #expect(result.contains("img"))
        // Both image and link should have link color applied
        let linkColorCount = result.components(separatedBy: "\u{1B}[38;2;96;165;250m").count - 1
        #expect(linkColorCount == 2)  // one for image, one for link
    }

    @Test("image does not match inside bold")
    func image_insideBold() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        // Image inside bold context — should not trigger image rendering
        let result = formatter.formatLine("**![img](https://a.com/i.png)**")
        // Bold markers should be processed, but image inside bold is suppressed
        #expect(result.contains("\u{1B}[1m"))  // bold applied
    }

    @Test("image URL with parentheses")
    func image_urlWithParens() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("![pic](https://example.com/pic_(1).png)")
        #expect(result.contains("📷"))
        #expect(result.contains("pic"))
    }

    @Test("unclosed image syntax falls through")
    func image_unclosed() {
        let formatter = StreamingMarkdownFormatter(profile: .trueColor, isTTY: true)
        let result = formatter.formatLine("![alt](https://example.com/unclosed")
        // Unclosed paren → not a valid image, treated as plain text
        #expect(!result.contains("📷"))
    }

    // MARK: - Test Helpers

    /// Strip ANSI escape sequences from a string for visible-length assertions.
    private func stripANSI(_ string: String) -> String {
        let pattern = "\u{1B}\\[[0-9;]*m"
        return string.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
    }
}
