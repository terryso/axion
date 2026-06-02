import Testing
import Foundation
@testable import AxionCLI

@Suite("TGErrorSanitizer")
struct TGErrorSanitizerTests {

    // MARK: - API Key Redaction

    @Test("Redacts OpenAI-style API keys")
    func redactOpenAIKey() {
        let raw = "Error: Invalid sk-abc123def456ghi789jkl012mno345 in request"
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(!result.contains("sk-abc123"))
        #expect(result.contains("[REDACTED_KEY]"))
    }

    @Test("Redacts Anthropic-style API keys with hyphens")
    func redactAnthropicKey() {
        let raw = "Error: Invalid sk-ant-api03-a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6 in request"
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(!result.contains("sk-ant"))
        #expect(result.contains("[REDACTED_KEY]"))
    }

    @Test("Redacts Bearer tokens")
    func redactBearerToken() {
        let raw = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def"
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(!result.contains("eyJhbGci"))
        #expect(result.contains("[REDACTED_TOKEN]"))
    }

    @Test("Redacts api_key parameter")
    func redactApiKeyParam() {
        let raw = "Request failed with api_key=sk-abc123def456ghi789"
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(!result.contains("sk-abc"))
    }

    // MARK: - Path Stripping

    @Test("Strips file paths to last component")
    func stripFilePaths() {
        let raw = "Error reading file /Users/nick/projects/app/config.json"
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(!result.contains("Users/nick"))
        #expect(result.contains("config.json"))
    }

    @Test("Strips /tmp paths")
    func stripTmpPaths() {
        let raw = "Error reading /tmp/axion-build/output.log"
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(!result.contains("/tmp/axion"))
        #expect(result.contains("output.log"))
    }

    // MARK: - Stack Trace Truncation

    @Test("Truncates stack traces to first line")
    func truncateStackTrace() {
        let raw = "Runtime error\n  at main.swift:42\n  at handler.swift:15\n  at router.swift:88"
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(result.contains("Runtime error"))
        #expect(result.contains("stack trace truncated"))
        #expect(!result.contains("handler.swift"))
    }

    // MARK: - HTTP JSON Error Extraction

    @Test("Extracts error.message from JSON body")
    func extractJSONErrorMessage() {
        let raw = "{\"error\": {\"message\": \"Rate limit exceeded\", \"type\": \"rate_limit\"}}"
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(result.contains("请求过于频繁"))
    }

    @Test("Extracts description from JSON body")
    func extractJSONDescription() {
        let raw = "{\"ok\": false, \"description\": \"Bad Request: can't parse entities\"}"
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(result == "请求格式错误")
    }

    // MARK: - Friendly Chinese Summaries

    @Test("Maps auth errors to Chinese")
    func mapAuthError() {
        let result = TGErrorSanitizer.sanitizeForTelegramError("401 Unauthorized")
        #expect(result == "认证失败，请检查 API Key 配置")
    }

    @Test("Maps rate limit to Chinese")
    func mapRateLimitError() {
        let result = TGErrorSanitizer.sanitizeForTelegramError("429 Too Many Requests")
        #expect(result == "请求过于频繁，请稍后重试")
    }

    @Test("Maps timeout to Chinese")
    func mapTimeoutError() {
        let result = TGErrorSanitizer.sanitizeForTelegramError("Connection timed out after 300s")
        #expect(result == "命令执行超时")
    }

    @Test("Maps connection failed to Chinese")
    func mapConnectionError() {
        let result = TGErrorSanitizer.sanitizeForTelegramError("Connection refused by server")
        #expect(result == "网络连接失败，请检查网络")
    }

    @Test("Maps 404 to Chinese")
    func mapNotFoundError() {
        let result = TGErrorSanitizer.sanitizeForTelegramError("Not found: 404")
        #expect(result == "请求的资源不存在")
    }

    @Test("Maps 403 to Chinese")
    func mapForbiddenError() {
        let result = TGErrorSanitizer.sanitizeForTelegramError("403 Forbidden")
        #expect(result == "权限不足，无法执行此操作")
    }

    @Test("Maps 500 to Chinese")
    func mapServerError() {
        let result = TGErrorSanitizer.sanitizeForTelegramError("Internal Server Error (500)")
        #expect(result == "服务器内部错误，请稍后重试")
    }

    @Test("Maps 400 to Chinese")
    func mapBadRequestError() {
        let result = TGErrorSanitizer.sanitizeForTelegramError("400 Bad Request")
        #expect(result == "请求格式错误")
    }

    // MARK: - Truncation

    @Test("Truncates messages over 800 chars")
    func truncateLongMessage() {
        let raw = String(repeating: "A", count: 1000)
        let result = TGErrorSanitizer.sanitizeForTelegramError(raw)
        #expect(result.count <= 803) // 800 + "..."
        #expect(result.hasSuffix("..."))
    }
}
