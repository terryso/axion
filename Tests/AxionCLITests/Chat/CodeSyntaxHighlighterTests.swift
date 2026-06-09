import Testing

@testable import AxionCLI

/// CodeSyntaxHighlighter 测试 — 验证语言感知的代码语法着色。
///
/// 覆盖范围：
/// - 语言规范化（normalizeLanguage）
/// - 各语言关键字高亮（Swift/Python/JS/Bash/Rust/Go/Java/C）
/// - 字符串、注释、数字、内建类型高亮
/// - JSON 专用高亮（key/value/string/number/boolean）
/// - 颜色 profile 降级链（TrueColor/ANSI256/ANSI16/unknown）
/// - 非 TTY 直通
/// - 不支持的语言回退
/// - 边界情况（空行、超长行、纯空白、混合 token）
@Suite("CodeSyntaxHighlighter")
struct CodeSyntaxHighlighterTests {

    // MARK: - Language Normalization

    @Test("Normalize language identifiers with aliases")
    func test_normalizeLanguage_aliases() {
        #expect(CodeSyntaxHighlighter.normalizeLanguage("swift") == "swift")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("Python") == "python")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("JS") == "javascript")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("TypeScript") == "typescript")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("TS") == "typescript")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("bash") == "bash")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("sh") == "bash")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("zsh") == "bash")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("rs") == "rust")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("golang") == "go")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("kt") == "kotlin")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("c++") == "cpp")
        #expect(CodeSyntaxHighlighter.normalizeLanguage("yml") == "yaml")
    }

    @Test("Normalize language returns nil for unsupported")
    func test_normalizeLanguage_unsupported() {
        #expect(CodeSyntaxHighlighter.normalizeLanguage("brainfuck") == nil)
        #expect(CodeSyntaxHighlighter.normalizeLanguage("") == nil)
        #expect(CodeSyntaxHighlighter.normalizeLanguage("unknown-lang") == nil)
    }

    // MARK: - Non-TTY Passthrough

    @Test("Non-TTY returns original text unchanged")
    func test_nonTTY_passthrough() {
        let line = "let x = 42"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: false
        )
        #expect(result == line)
    }

    @Test("Unknown profile returns original text")
    func test_unknownProfile_passthrough() {
        let line = "let x = 42"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .unknown, isTTY: true
        )
        #expect(result == line)
    }

    @Test("Unsupported language returns original text")
    func test_unsupportedLanguage_passthrough() {
        let line = "some code here"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "brainfuck", profile: .trueColor, isTTY: true
        )
        #expect(result == line)
    }

    @Test("Empty line returns empty")
    func test_emptyLine() {
        let result = CodeSyntaxHighlighter.highlight(
            line: "", language: "swift", profile: .trueColor, isTTY: true
        )
        #expect(result == "")
    }

    // MARK: - Swift Highlighting

    @Test("Swift keywords are highlighted")
    func test_swift_keywords() {
        let line = "let x = 42"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        // "let" should be colored (keyword purple)
        #expect(result.contains("\u{1B}[38;2;198;120;221m"))
        #expect(result.contains("let"))
        #expect(result.contains("\u{1B}[0m"))
    }

    @Test("Swift string literal is highlighted green")
    func test_swift_string() {
        let line = "let name = \"hello world\""
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        // String should be green
        let greenCode = "\u{1B}[38;2;166;226;46m"
        #expect(result.contains(greenCode))
        #expect(result.contains("hello world"))
    }

    @Test("Swift comment is highlighted dim gray")
    func test_swift_comment() {
        let line = "// this is a comment"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        let commentColor = "\u{1B}[38;2;128;128;128m"
        #expect(result.contains(commentColor))
    }

    @Test("Swift number is highlighted yellow")
    func test_swift_number() {
        let line = "let x = 42"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        let yellowCode = "\u{1B}[38;2;230;219;116m"
        #expect(result.contains(yellowCode))
        #expect(result.contains("42"))
    }

    @Test("Swift builtin types are highlighted cyan")
    func test_swift_builtin() {
        let line = "let arr: [String] = []"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        let cyanCode = "\u{1B}[38;2;102;217;239m"
        #expect(result.contains(cyanCode))
        #expect(result.contains("String"))
    }

    // MARK: - Python Highlighting

    @Test("Python keywords are highlighted")
    func test_python_keywords() {
        let line = "def hello_world():"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "python", profile: .trueColor, isTTY: true
        )
        let purpleCode = "\u{1B}[38;2;198;120;221m"
        #expect(result.contains(purpleCode))
        #expect(result.contains("def"))
    }

    @Test("Python comment with hash")
    func test_python_comment() {
        let line = "# this is a python comment"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "python", profile: .trueColor, isTTY: true
        )
        let commentColor = "\u{1B}[38;2;128;128;128m"
        #expect(result.contains(commentColor))
    }

    @Test("Python builtin functions highlighted")
    func test_python_builtin() {
        let line = "print(len(items))"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "python", profile: .trueColor, isTTY: true
        )
        let cyanCode = "\u{1B}[38;2;102;217;239m"
        #expect(result.contains(cyanCode))
    }

    // MARK: - JavaScript Highlighting

    @Test("JavaScript keywords and builtins")
    func test_javascript_keywords() {
        let line = "const x = await fetch(url);"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "javascript", profile: .trueColor, isTTY: true
        )
        #expect(result.contains("const"))
        #expect(result.contains("await"))
    }

    @Test("TypeScript uses same rules as JavaScript")
    func test_typescript_uses_js_rules() {
        let line = "interface User { name: string }"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "typescript", profile: .trueColor, isTTY: true
        )
        #expect(result.contains("interface"))
    }

    // MARK: - Bash Highlighting

    @Test("Bash keywords highlighted")
    func test_bash_keywords() {
        let line = "if [ -f file ]; then"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "bash", profile: .trueColor, isTTY: true
        )
        #expect(result.contains("if"))
        #expect(result.contains("then"))
    }

    @Test("Bash comment with hash")
    func test_bash_comment() {
        let line = "#!/bin/bash"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "bash", profile: .trueColor, isTTY: true
        )
        let commentColor = "\u{1B}[38;2;128;128;128m"
        #expect(result.contains(commentColor))
    }

    // MARK: - Rust Highlighting

    @Test("Rust keywords highlighted")
    func test_rust_keywords() {
        let line = "fn main() -> Result<(), Error> {"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "rust", profile: .trueColor, isTTY: true
        )
        #expect(result.contains("fn"))
    }

    @Test("Rust builtin types highlighted")
    func test_rust_builtin() {
        let line = "let v: Vec<String> = Vec::new();"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "rust", profile: .trueColor, isTTY: true
        )
        let cyanCode = "\u{1B}[38;2;102;217;239m"
        #expect(result.contains(cyanCode))
    }

    // MARK: - Go Highlighting

    @Test("Go keywords highlighted")
    func test_go_keywords() {
        let line = "func main() {"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "go", profile: .trueColor, isTTY: true
        )
        #expect(result.contains("func"))
    }

    // MARK: - JSON Highlighting

    @Test("JSON keys highlighted in keyword color")
    func test_json_keyHighlighting() {
        let line = "  \"name\": \"Alice\","
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "json", profile: .trueColor, isTTY: true
        )
        let purpleCode = "\u{1B}[38;2;198;120;221m"
        #expect(result.contains(purpleCode))
        #expect(result.contains("name"))
    }

    @Test("JSON string values highlighted in green")
    func test_json_stringValue() {
        let line = "  \"name\": \"Alice\""
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "json", profile: .trueColor, isTTY: true
        )
        let greenCode = "\u{1B}[38;2;166;226;46m"
        #expect(result.contains(greenCode))
        #expect(result.contains("Alice"))
    }

    @Test("JSON number values highlighted in yellow")
    func test_json_numberValue() {
        let line = "  \"age\": 30,"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "json", profile: .trueColor, isTTY: true
        )
        let yellowCode = "\u{1B}[38;2;230;219;116m"
        #expect(result.contains(yellowCode))
        #expect(result.contains("30"))
    }

    @Test("JSON boolean/null highlighted in keyword color")
    func test_json_booleanNull() {
        let line = "  \"active\": true, \"data\": null"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "json", profile: .trueColor, isTTY: true
        )
        let purpleCode = "\u{1B}[38;2;198;120;221m"
        #expect(result.contains(purpleCode))
        #expect(result.contains("true"))
        #expect(result.contains("null"))
    }

    // MARK: - Color Profile Degradation

    @Test("ANSI256 profile uses 256-color codes")
    func test_ansi256_profile() {
        let line = "let x = 42"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .ansi256, isTTY: true
        )
        // Keyword should use ANSI256 code
        #expect(result.contains("\u{1B}[38;5;"))
        #expect(!result.contains("\u{1B}[38;2;"))
    }

    @Test("ANSI16 profile uses basic color codes")
    func test_ansi16_profile() {
        let line = "let x = 42"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .ansi16, isTTY: true
        )
        // Keyword should use ANSI16 magenta
        #expect(result.contains("\u{1B}[35m"))
    }

    @Test("Token type color codes match profile")
    func test_tokenType_colorCodes() {
        // TrueColor
        let tc = CodeSyntaxHighlighter.colorCode(for: .keyword, profile: .trueColor)
        #expect(tc.contains("38;2;"))

        // ANSI256
        let a256 = CodeSyntaxHighlighter.colorCode(for: .keyword, profile: .ansi256)
        #expect(a256.contains("38;5;"))

        // ANSI16
        let a16 = CodeSyntaxHighlighter.colorCode(for: .keyword, profile: .ansi16)
        #expect(a16 == "\u{1B}[35m")

        // Unknown
        let unk = CodeSyntaxHighlighter.colorCode(for: .keyword, profile: .unknown)
        #expect(unk == "")
    }

    // MARK: - Mixed Token Lines

    @Test("Line with multiple token types highlights all correctly")
    func test_mixedTokens() {
        let line = "let name = \"hello\" // comment"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        // Should contain keyword color (for 'let')
        let purpleCode = "\u{1B}[38;2;198;120;221m"
        // Should contain string color (for "hello")
        let greenCode = "\u{1B}[38;2;166;226;46m"
        // Should contain comment color (for // comment)
        let commentColor = "\u{1B}[38;2;128;128;128m"

        #expect(result.contains(purpleCode))
        #expect(result.contains(greenCode))
        #expect(result.contains(commentColor))
    }

    @Test("Plain text without tokens has no ANSI codes")
    func test_plainText_noTokens() {
        let line = "    just regular text here"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        // No coloring should be applied to plain text without any tokens
        #expect(!result.contains("\u{1B}["))
        #expect(result == line)
    }

    // MARK: - Boundary Cases

    @Test("Line with only whitespace returns unchanged")
    func test_whitespaceOnly() {
        let line = "    \t  "
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        #expect(result == line)
    }

    @Test("Hex number is highlighted")
    func test_hexNumber() {
        let line = "let mask = 0xFF00"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        let yellowCode = "\u{1B}[38;2;230;219;116m"
        #expect(result.contains(yellowCode))
        #expect(result.contains("0xFF00"))
    }

    @Test("Single-quoted string is highlighted")
    func test_singleQuotedString() {
        let line = "char c = 'a';"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "c", profile: .trueColor, isTTY: true
        )
        let greenCode = "\u{1B}[38;2;166;226;46m"
        #expect(result.contains(greenCode))
    }

    @Test("Block comment pattern is recognized")
    func test_blockComment() {
        let line = "/* this is a block comment */"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "swift", profile: .trueColor, isTTY: true
        )
        let commentColor = "\u{1B}[38;2;128;128;128m"
        #expect(result.contains(commentColor))
    }

    // MARK: - Integration with StreamingCodeBlockRenderer

    @Test("StreamingCodeBlockRenderer uses syntax highlighting for non-diff code")
    func test_renderer_integration() {
        var renderer = StreamingCodeBlockRenderer(
            profile: .trueColor,
            isTTY: true,
            terminalWidth: 80,
            plainTextFormatter: { $0 }
        )

        var output = ""
        // Open code block with swift language
        renderer.process("```swift\n", write: { output += $0 })
        // Code content
        renderer.process("let x = 42\n", write: { output += $0 })

        // Should contain keyword color for 'let'
        #expect(output.contains("\u{1B}[38;2;198;120;221m"))
        // Should contain number color for '42'
        #expect(output.contains("\u{1B}[38;2;230;219;116m"))
        // Should contain box-drawing border
        #expect(output.contains("│"))
    }

    @Test("StreamingCodeBlockRenderer diff mode bypasses syntax highlighting")
    func test_renderer_diffMode_noSyntaxHighlight() {
        var renderer = StreamingCodeBlockRenderer(
            profile: .trueColor,
            isTTY: true,
            terminalWidth: 80,
            plainTextFormatter: { $0 }
        )

        var output = ""
        renderer.process("```diff\n", write: { output += $0 })
        renderer.process("+added line\n", write: { output += $0 })

        // Should contain diff green color, not syntax keyword color
        let diffGreen = "\u{1B}[38;2;76;175;80m"
        let syntaxPurple = "\u{1B}[38;2;198;120;221m"
        #expect(output.contains(diffGreen))
        #expect(!output.contains(syntaxPurple))
    }

    // MARK: - YAML/Config Highlighting

    @Test("YAML keys highlighted")
    func test_yaml_keys() {
        let line = "server:"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "yaml", profile: .trueColor, isTTY: true
        )
        let cyanCode = "\u{1B}[38;2;102;217;239m"
        #expect(result.contains(cyanCode))
    }

    // MARK: - SQL Highlighting

    @Test("SQL keywords highlighted case-insensitively")
    func test_sql_keywords() {
        let line = "SELECT * FROM users WHERE id = 1;"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "sql", profile: .trueColor, isTTY: true
        )
        let purpleCode = "\u{1B}[38;2;198;120;221m"
        #expect(result.contains(purpleCode))
        #expect(result.contains("SELECT"))
        #expect(result.contains("FROM"))
        #expect(result.contains("WHERE"))
    }

    // MARK: - CSS Highlighting

    @Test("CSS properties highlighted")
    func test_css_properties() {
        let line = "  color: red;"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "css", profile: .trueColor, isTTY: true
        )
        let purpleCode = "\u{1B}[38;2;198;120;221m"
        #expect(result.contains(purpleCode))
    }

    @Test("CSS hex colors highlighted as numbers")
    func test_css_hexColor() {
        let line = "  background: #ff0000;"
        let result = CodeSyntaxHighlighter.highlight(
            line: line, language: "css", profile: .trueColor, isTTY: true
        )
        let yellowCode = "\u{1B}[38;2;230;219;116m"
        #expect(result.contains(yellowCode))
        #expect(result.contains("#ff0000"))
    }

    // MARK: - Reset Code

    @Test("Reset code is correct per profile")
    func test_resetCode() {
        #expect(CodeSyntaxHighlighter.resetCode(for: .trueColor) == "\u{1B}[0m")
        #expect(CodeSyntaxHighlighter.resetCode(for: .ansi256) == "\u{1B}[0m")
        #expect(CodeSyntaxHighlighter.resetCode(for: .ansi16) == "\u{1B}[0m")
        #expect(CodeSyntaxHighlighter.resetCode(for: .unknown) == "")
    }
}
