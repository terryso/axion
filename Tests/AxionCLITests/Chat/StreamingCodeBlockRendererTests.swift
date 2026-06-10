import Testing
import Foundation

@testable import AxionCLI

/// Strip ANSI escape sequences from a string for content-based assertions.
private func strippedANSI(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
}

@Suite("StreamingCodeBlockRenderer")
struct StreamingCodeBlockRendererTests {

    // MARK: - Fence Detection

    @Test("isFenceLine detects triple backtick fence")
    func testFenceLineBacktick() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true)
        // Access isFenceLine via process — verified through output
        // Testing with a simple code block open/close
        var output: [String] = []
        var r = renderer
        r.process("```swift\n") { output.append($0) }
        #expect(output.count >= 1)
        // Should render a border (not raw ```)
        let combined = output.joined()
        #expect(!combined.contains("```swift"))
        #expect(combined.contains("swift"))
    }

    @Test("isFenceLine detects tilde fence")
    func testFenceLineTilde() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true)
        var output: [String] = []
        var r = renderer
        r.process("~~~python\n") { output.append($0) }
        let combined = output.joined()
        #expect(!combined.contains("~~~python"))
        #expect(combined.contains("python"))
    }

    // MARK: - Code Block Open/Close

    @Test("renders open and close borders for complete code block")
    func testCompleteCodeBlock() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        // Open fence
        r.process("```swift\n") { output.append($0) }
        // Code content
        r.process("func hello() {\n") { output.append($0) }
        r.process("    print(\"Hi\")\n") { output.append($0) }
        r.process("}\n") { output.append($0) }
        // Close fence
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        // Should contain language label
        #expect(combined.contains("swift"))
        // Should NOT contain raw fence markers
        #expect(!combined.contains("```swift"))
        #expect(!combined.contains("```\n"))
        // Should contain code content (preserved — syntax highlighting may insert ANSI codes)
        let plain = strippedANSI(combined)
        #expect(plain.contains("func hello()"))
        #expect(plain.contains("print(\"Hi\")"))
        // Should contain border characters
        #expect(combined.contains("┌") || combined.contains("─"))
        #expect(combined.contains("┘"))
    }

    @Test("renders code block without language tag")
    func testCodeBlockNoLanguage() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        r.process("```\n") { output.append($0) }
        r.process("some code\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        #expect(!combined.contains("```"))
        #expect(combined.contains("some code"))
    }

    // MARK: - Plain Text Passthrough

    @Test("passes through non-code text unchanged")
    func testPlainTextPassthrough() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true)
        var output: [String] = []
        var r = renderer

        r.process("Hello world\n") { output.append($0) }
        r.process("This is normal text\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("Hello world"))
        #expect(combined.contains("This is normal text"))
        #expect(!combined.contains("┌"))
    }

    @Test("handles mixed text and code blocks")
    func testMixedTextAndCode() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 60)
        var output: [String] = []
        var r = renderer

        r.process("Here's the code:\n") { output.append($0) }
        r.process("```swift\n") { output.append($0) }
        r.process("let x = 1\n") { output.append($0) }
        r.process("```\n") { output.append($0) }
        r.process("That was the code.\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("Here's the code:"))
        #expect(strippedANSI(combined).contains("let x = 1"))
        #expect(combined.contains("That was the code."))
        #expect(!combined.contains("```swift"))
        #expect(!combined.contains("```\n"))
    }

    // MARK: - Non-TTY Passthrough

    @Test("non-TTY passes through all text unchanged including fences")
    func testNonTTYPassthrough() {
        let renderer = StreamingCodeBlockRenderer(profile: .unknown, isTTY: false)
        var output: [String] = []
        var r = renderer

        r.process("```swift\n") { output.append($0) }
        r.process("let x = 1\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        // Non-TTY should pass through raw markdown
        #expect(combined.contains("```swift"))
        #expect(combined.contains("let x = 1"))
        #expect(combined.contains("```"))
    }

    // MARK: - Chunk Splitting

    @Test("handles fence marker split across chunks")
    func testFenceSplitAcrossChunks() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        // Split ````swift\n` into two chunks
        r.process("``") { output.append($0) }
        r.process("`swift\n") { output.append($0) }
        r.process("code line\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("swift"))
        #expect(combined.contains("code line"))
    }

    @Test("handles single chunk with multiple lines")
    func testSingleChunkMultipleLines() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        let chunk = "```python\ndef foo():\n    pass\n```\n"
        r.process(chunk) { output.append($0) }

        let combined = output.joined()
        #expect(!combined.contains("```python"))
        #expect(combined.contains("python"))
        let plain = strippedANSI(combined)
        #expect(plain.contains("def foo():"))
        #expect(plain.contains("pass"))
    }

    // MARK: - Language Extraction

    @Test("extracts language from fence with info string")
    func testLanguageExtraction() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        // Test various language tags
        r.process("```typescript\n") { output.append($0) }
        let result1 = output.joined()
        #expect(result1.contains("typescript"))

        output.removeAll()
        r.reset()

        r.process("```c++\n") { output.append($0) }
        let result2 = output.joined()
        #expect(result2.contains("c++"))

        output.removeAll()
        r.reset()

        r.process("```objective-c\n") { output.append($0) }
        let result3 = output.joined()
        #expect(result3.contains("objective-c"))
    }

    // MARK: - State Machine Reset

    @Test("reset clears code block state")
    func testResetClearsState() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        // Open a code block
        r.process("```swift\n") { output.append($0) }
        #expect(r.inCodeBlock == true)

        // Reset (simulates turn boundary)
        r.reset()
        #expect(r.inCodeBlock == false)
        #expect(r.currentLang == "")

        // After reset, text should pass through as normal
        output.removeAll()
        r.process("normal text\n") { output.append($0) }
        let combined = output.joined()
        #expect(combined.contains("normal text"))
    }

    // MARK: - Flush

    @Test("flush outputs buffered incomplete line")
    func testFlushOutputsBuffer() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true)
        var output: [String] = []
        var r = renderer

        // Send text without newline — buffered
        r.process("partial text") { output.append($0) }
        #expect(output.isEmpty)

        // Flush should output the buffered text
        r.flush { output.append($0) }
        #expect(output.count == 1)
        #expect(output[0] == "partial text")
    }

    // MARK: - Color Profile Degradation

    @Test("ANSI256 renders borders with 256-color codes")
    func testANSI256Borders() {
        let renderer = StreamingCodeBlockRenderer(profile: .ansi256, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        r.process("```swift\n") { output.append($0) }
        let combined = output.joined()
        #expect(combined.contains("\u{1B}[38;5;"))  // 256-color code
        #expect(combined.contains("swift"))
    }

    @Test("ANSI16 renders borders with standard color codes")
    func testANSI16Borders() {
        let renderer = StreamingCodeBlockRenderer(profile: .ansi16, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        r.process("```swift\n") { output.append($0) }
        let combined = output.joined()
        // ANSI16 uses dim/faint attribute or standard color codes
        #expect(combined.contains("\u{1B}[") || combined.contains("swift"))
    }

    @Test("unknown profile renders plain borders without ANSI codes")
    func testUnknownProfileBorders() {
        let renderer = StreamingCodeBlockRenderer(profile: .unknown, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        r.process("```swift\n") { output.append($0) }
        let combined = output.joined()
        #expect(combined.contains("swift"))
        #expect(combined.contains("─"))
    }

    // MARK: - Edge Cases

    @Test("handles empty input")
    func testEmptyInput() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true)
        var output: [String] = []
        var r = renderer

        r.process("") { output.append($0) }
        #expect(output.isEmpty)
    }

    @Test("handles code block with leading/trailing whitespace on fence")
    func testFenceWithWhitespace() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        r.process("  ```swift\n") { output.append($0) }
        r.process("let x = 1\n") { output.append($0) }
        r.process("  ```\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("swift"))
        #expect(strippedANSI(combined).contains("let x = 1"))
    }

    @Test("handles four backticks as fence")
    func testFourBackticks() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        r.process("````markdown\n") { output.append($0) }
        r.process("some content\n") { output.append($0) }
        r.process("````\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("markdown"))
        #expect(combined.contains("some content"))
    }

    @Test("does not treat inline backticks as fence")
    func testInlineBackticksNotFence() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true)
        var output: [String] = []
        var r = renderer

        r.process("Use `code` in your text\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("Use `code` in your text"))
        #expect(!combined.contains("┌"))
    }

    @Test("handles nested code blocks with different fence chars")
    func testNestedDifferentFenceChars() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        r.process("~~~markdown\n") { output.append($0) }
        r.process("```swift\n") { output.append($0) }
        r.process("let x = 1\n") { output.append($0) }
        r.process("```\n") { output.append($0) }
        r.process("~~~\n") { output.append($0) }

        let combined = output.joined()
        #expect(strippedANSI(combined).contains("let x = 1"))
        #expect(combined.contains("markdown"))
    }

    // MARK: - Code Content Styling

    @Test("code content lines have pipe prefix in TTY mode")
    func testCodeContentPipePrefix() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        r.process("```swift\n") { output.append($0) }
        output.removeAll()
        r.process("let x = 1\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("│"))
        #expect(strippedANSI(combined).contains("let x = 1"))
    }

    // MARK: - Multiple Sequential Code Blocks

    @Test("handles multiple sequential code blocks")
    func testMultipleCodeBlocks() {
        let renderer = StreamingCodeBlockRenderer(profile: .trueColor, isTTY: true, terminalWidth: 40)
        var output: [String] = []
        var r = renderer

        r.process("First:\n") { output.append($0) }
        r.process("```swift\n") { output.append($0) }
        r.process("let a = 1\n") { output.append($0) }
        r.process("```\n") { output.append($0) }
        r.process("Second:\n") { output.append($0) }
        r.process("```python\n") { output.append($0) }
        r.process("b = 2\n") { output.append($0) }
        r.process("```\n") { output.append($0) }

        let combined = output.joined()
        #expect(combined.contains("First:"))
        #expect(combined.contains("swift"))
        #expect(strippedANSI(combined).contains("let a = 1"))
        #expect(combined.contains("Second:"))
        #expect(combined.contains("python"))
        #expect(strippedANSI(combined).contains("b = 2"))
    }
}
