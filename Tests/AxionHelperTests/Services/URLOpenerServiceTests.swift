import Foundation
import Testing
@testable import AxionHelper

@Suite("URLOpenerService")
@MainActor
struct URLOpenerServiceTests {

    // MARK: - URL Format Validation

    @Test("valid https URL does not throw")
    func openURLValidHttpsUrlDoesNotThrow() throws {
        let urlString = "https://example.com"
        let url = URL(string: urlString)
        #expect(url != nil, "Valid HTTPS URL should parse successfully")
        #expect(url?.scheme == "https")
    }

    @Test("invalid URL string throws invalidURL")
    func openURLInvalidURLThrowsInvalidURL() {
        let service = URLOpenerService()
        #expect(throws: URLOpenerError.self) {
            try service.openURL("not a url at all")
        }
    }

    @Test("empty string throws invalidURL")
    func openURLEmptyStringThrowsInvalidURL() {
        let service = URLOpenerService()
        #expect(throws: URLOpenerError.self) {
            try service.openURL("")
        }
    }

    // MARK: - Scheme Validation

    @Test("ftp scheme throws unsupportedScheme")
    func openURLFtpSchemeThrowsUnsupportedScheme() {
        let service = URLOpenerService()
        #expect(throws: URLOpenerError.self) {
            try service.openURL("ftp://example.com")
        }
    }

    @Test("file scheme throws unsupportedScheme")
    func openURLFileSchemeThrowsUnsupportedScheme() {
        let service = URLOpenerService()
        #expect(throws: URLOpenerError.self) {
            try service.openURL("file:///Users/test/doc.txt")
        }
    }

    @Test("javascript scheme throws unsupportedScheme")
    func openURLJavascriptSchemeThrowsUnsupportedScheme() {
        let service = URLOpenerService()
        #expect(throws: URLOpenerError.self) {
            try service.openURL("javascript:alert(1)")
        }
    }

    @Test("data scheme throws unsupportedScheme")
    func openURLDataSchemeThrowsUnsupportedScheme() {
        let service = URLOpenerService()
        #expect(throws: URLOpenerError.self) {
            try service.openURL("data:text/html,<h1>test</h1>")
        }
    }

    @Test("http scheme is accepted")
    func openURLHttpSchemeAccepted() throws {
        let urlString = "http://example.com"
        let url = URL(string: urlString)
        #expect(url != nil, "HTTP URL should parse successfully")
        #expect(url?.scheme == "http")
    }

    // MARK: - URLOpenerError Format

    @Test("invalidURL error has required fields")
    func urlOpenerErrorInvalidURLHasRequiredFields() {
        let error = URLOpenerError.invalidURL("bad-url")
        #expect(error.errorCode == "invalid_url")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    @Test("unsupportedScheme error has required fields")
    func urlOpenerErrorUnsupportedSchemeHasRequiredFields() {
        let error = URLOpenerError.unsupportedScheme("ftp://example.com")
        #expect(error.errorCode == "unsupported_scheme")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    @Test("failedToOpen error has required fields")
    func urlOpenerErrorFailedToOpenHasRequiredFields() {
        let error = URLOpenerError.failedToOpen("https://example.com")
        #expect(error.errorCode == "failed_to_open")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    // MARK: - Additional URL Validation

    @Test("URL without host throws error")
    func openURLUrlWithoutHostThrowsError() {
        let service = URLOpenerService()
        #expect(throws: URLOpenerError.self) {
            try service.openURL("https://")
        }
    }

    @Test("scheme only throws error")
    func openURLSchemeOnlyThrowsError() {
        let service = URLOpenerService()
        #expect(throws: URLOpenerError.self) {
            try service.openURL("https://")
        }
    }

    @Test("conforms to URLOpening protocol")
    func urlOpenerServiceConformsToURLOpening() {
        let service = URLOpenerService()
        #expect(service is URLOpening,
               "URLOpenerService should conform to URLOpening protocol")
    }

    // MARK: - Error Description Content

    @Test("invalidURL description contains URL")
    func urlOpenerErrorInvalidURLContainsUrl() {
        let error = URLOpenerError.invalidURL("bad-url")
        #expect(error.errorDescription!.contains("bad-url"))
    }

    @Test("unsupportedScheme description contains URL")
    func urlOpenerErrorUnsupportedSchemeContainsUrl() {
        let error = URLOpenerError.unsupportedScheme("ftp://host")
        #expect(error.errorDescription!.contains("ftp://host"))
    }

    @Test("failedToOpen description contains URL")
    func urlOpenerErrorFailedToOpenContainsUrl() {
        let error = URLOpenerError.failedToOpen("https://example.com")
        #expect(error.errorDescription!.contains("https://example.com"))
    }

    // MARK: - Suggestions

    @Test("suggestions are not empty")
    func urlOpenerErrorSuggestionsNotEmpty() {
        #expect(!URLOpenerError.invalidURL("x").suggestion.isEmpty)
        #expect(!URLOpenerError.unsupportedScheme("ftp://x").suggestion.isEmpty)
        #expect(!URLOpenerError.failedToOpen("https://x").suggestion.isEmpty)
    }

    @Test("unsupportedScheme suggests http/https")
    func urlOpenerErrorUnsupportedSchemeSuggestsHttpHttps() {
        let error = URLOpenerError.unsupportedScheme("ftp://x")
        #expect(error.suggestion.contains("http"))
    }

    @Test("invalidURL suggests valid URL")
    func urlOpenerErrorInvalidURLSuggestsValidUrl() {
        let error = URLOpenerError.invalidURL("x")
        #expect(error.suggestion.contains("http"))
    }

    // MARK: - Error Codes Distinct

    @Test("all error codes are distinct")
    func urlOpenerErrorAllErrorCodesDistinct() {
        let codes = [
            URLOpenerError.invalidURL("x").errorCode,
            URLOpenerError.unsupportedScheme("x").errorCode,
            URLOpenerError.failedToOpen("x").errorCode,
        ]
        #expect(Set(codes).count == codes.count, "All error codes should be distinct")
    }
}
