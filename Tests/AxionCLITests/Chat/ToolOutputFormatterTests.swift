import Foundation
import Testing

@testable import AxionCLI

// MARK: - ToolOutputFormatter Tests

@Suite("ToolOutputFormatter")
struct ToolOutputFormatterTests {

    // MARK: - formatJSONCompact

    @Test("formatJSONCompact: 紧凑化简单 JSON 对象")
    func formatJSONCompactSimpleObject() {
        let input = "{\"name\":\"test\",\"value\":42}"
        let result = ToolOutputFormatter.formatJSONCompact(input)
        #expect(result == "{\"name\": \"test\", \"value\": 42}")
    }

    @Test("formatJSONCompact: 紧凑化嵌套 JSON")
    func formatJSONCompactNested() {
        let input = "{\"items\":[\"a\",\"b\",\"c\"]}"
        let result = ToolOutputFormatter.formatJSONCompact(input)
        #expect(result == "{\"items\": [\"a\", \"b\", \"c\"]}")
    }

    @Test("formatJSONCompact: 无效 JSON 返回 nil")
    func formatJSONCompactInvalidJSON() {
        let input = "not json at all"
        let result = ToolOutputFormatter.formatJSONCompact(input)
        #expect(result == nil)
    }

    @Test("formatJSONCompact: 空对象保持不变")
    func formatJSONCompactEmptyObject() {
        let input = "{}"
        let result = ToolOutputFormatter.formatJSONCompact(input)
        #expect(result == "{}")
    }

    @Test("formatJSONCompact: 包含转义引号的字符串")
    func formatJSONCompactEscapedQuotes() {
        let input = "{\"msg\":\"hello \\\"world\\\"\"}"
        let result = ToolOutputFormatter.formatJSONCompact(input)
        #expect(result == "{\"msg\": \"hello \\\"world\\\"\"}")
    }

    @Test("formatJSONCompact: JSON 数组")
    func formatJSONCompactArray() {
        let input = "[1,2,3]"
        let result = ToolOutputFormatter.formatJSONCompact(input)
        #expect(result == "[1, 2, 3]")
    }

    // MARK: - truncateText

    @Test("truncateText: 短文本不截断")
    func truncateTextShortText() {
        let result = ToolOutputFormatter.truncateText("hello", maxLength: 100)
        #expect(result == "hello")
    }

    @Test("truncateText: 长文本截断并加省略号")
    func truncateTextLongText() {
        let input = String(repeating: "a", count: 200)
        let result = ToolOutputFormatter.truncateText(input, maxLength: 10)
        #expect(result.unicodeScalars.count == 10)
        #expect(result.hasSuffix("…"))
    }

    @Test("truncateText: maxLength 等于文本长度不截断")
    func truncateTextExactLength() {
        let input = "hello"
        let result = ToolOutputFormatter.truncateText(input, maxLength: 5)
        #expect(result == "hello")
    }

    @Test("truncateText: maxLength 为 0 返回空字符串")
    func truncateTextZeroMaxLength() {
        let result = ToolOutputFormatter.truncateText("hello", maxLength: 0)
        #expect(result == "")
    }

    @Test("truncateText: maxLength 为 1 返回省略号")
    func truncateTextMaxLengthOne() {
        let result = ToolOutputFormatter.truncateText("hello", maxLength: 1)
        #expect(result == "…")
    }

    @Test("truncateText: maxLength 为 2 截断到 1 字符加省略号")
    func truncateTextMaxLengthTwo() {
        let result = ToolOutputFormatter.truncateText("hello", maxLength: 2)
        #expect(result == "h…")
    }

    // MARK: - truncatePathCenter

    @Test("truncatePathCenter: 短路径不截断")
    func truncatePathCenterShortPath() {
        let result = ToolOutputFormatter.truncatePathCenter("/Users/nick/file.txt", maxWidth: 100)
        #expect(result == "/Users/nick/file.txt")
    }

    @Test("truncatePathCenter: 长路径保留首尾段")
    func truncatePathCenterLongPath() {
        let path = "/Users/nick/very/deep/nested/path/file.txt"
        let result = ToolOutputFormatter.truncatePathCenter(path, maxWidth: 30)
        // 应该包含首段 Users 和末段 file.txt
        #expect(result.contains("Users"))
        #expect(result.contains("file.txt"))
        #expect(result.contains("…"))
    }

    @Test("truncatePathCenter: maxWidth 为 0 返回空字符串")
    func truncatePathCenterZeroWidth() {
        let result = ToolOutputFormatter.truncatePathCenter("/some/path", maxWidth: 0)
        #expect(result == "")
    }

    @Test("truncatePathCenter: 无前导斜杠的路径")
    func truncatePathCenterNoLeadingSlash() {
        let path = "very/deep/nested/path/to/some/important/file.txt"
        let result = ToolOutputFormatter.truncatePathCenter(path, maxWidth: 30)
        #expect(result.contains("very"))
        #expect(result.contains("file.txt"))
        #expect(result.contains("…"))
    }

    // MARK: - formatToolResult

    @Test("formatToolResult: 截图内容返回 [screenshot captured]")
    func formatToolResultScreenshot() {
        let result = ToolOutputFormatter.formatToolResult(
            "{\"action\":\"screenshot\",\"data\":\"abc\"}"
        )
        #expect(result == "[screenshot captured]")
    }

    @Test("formatToolResult: base64 内容返回 [screenshot captured]")
    func formatToolResultBase64() {
        let result = ToolOutputFormatter.formatToolResult(
            "Image data: Base64 encoded content here"
        )
        #expect(result == "[screenshot captured]")
    }

    @Test("formatToolResult: JSON 对象紧凑化")
    func formatToolResultJSONObject() {
        let input = "{\"name\":\"test\",\"count\":42,\"items\":[\"a\",\"b\"]}"
        let result = ToolOutputFormatter.formatToolResult(input, maxWidth: 120)
        // 应该包含空格（紧凑 JSON 格式化）
        #expect(result.contains("\"name\":"))
        #expect(result.contains("\"count\":"))
    }

    @Test("formatToolResult: 多行文本截断到 maxLines 并显示剩余行数")
    func formatToolResultMultiLine() {
        let input = "line1\nline2\nline3\nline4\nline5\nline6"
        let result = ToolOutputFormatter.formatToolResult(input, maxWidth: 120, maxLines: 3)
        #expect(result.contains("line1"))
        #expect(result.contains("line2"))
        #expect(result.contains("line3"))
        #expect(result.contains("3 more lines"))
        #expect(!result.contains("line4"))
    }

    @Test("formatToolResult: 单行文本直接截断")
    func formatToolResultSingleLine() {
        let input = String(repeating: "x", count: 200)
        let result = ToolOutputFormatter.formatToolResult(input, maxWidth: 50)
        #expect(result.unicodeScalars.count <= 50)
        #expect(result.hasSuffix("…"))
    }

    @Test("formatToolResult: 空内容返回 [empty]")
    func formatToolResultEmpty() {
        let result = ToolOutputFormatter.formatToolResult("", maxWidth: 120)
        #expect(result == "[empty]")
    }

    @Test("formatToolResult: 仅含 ANSI 转义码的行被过滤后返回 [empty]")
    func formatToolResultOnlyANSI() {
        let result = ToolOutputFormatter.formatToolResult(
            "\u{1B}[32m\u{1B}[0m",
            maxWidth: 120
        )
        #expect(result == "[empty]")
    }

    // MARK: - Integration: summarizeToolContent uses ToolOutputFormatter

    @Test("summarizeToolContent: JSON 通过紧凑格式化展示")
    func summarizeToolContentJSON() {
        let input = "{\"status\":\"ok\",\"data\":{\"items\":[1,2,3]}}"
        let result = summarizeToolContent(input)
        #expect(result.contains("\"status\":"))
        #expect(result.contains("\"ok\""))
    }

    @Test("summarizeToolContent: 多行内容显示剩余行数")
    func summarizeToolContentMultiLineWithMoreLines() {
        let input = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let result = summarizeToolContent(input, maxLines: 3)
        #expect(result.contains("7 more lines"))
    }
}
