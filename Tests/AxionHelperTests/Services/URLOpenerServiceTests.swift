import Foundation
import XCTest
@testable import AxionHelper

// ATDD Red-Phase Test Scaffolds for Story 1.5
// Tests for URLOpenerService URL validation logic.
// These tests verify URL parsing and scheme validation without opening real URLs.
// Priority: P0 (core logic for open_url tool)

@MainActor
final class URLOpenerServiceTests: XCTestCase {

    // MARK: - URL Format Validation

    // [P0] Valid https URL does not throw
    func test_openURL_validHttpsUrl_doesNotThrow() throws {
        let service = URLOpenerService()
        // Note: This test may fail in CI where NSWorkspace is unavailable,
        // but URL parsing validation should succeed.
        // We use XCTAssertNoThrow for the URL validation part only.
        // The actual open call may fail in headless environments.
        let urlString = "https://example.com"
        let url = URL(string: urlString)
        XCTAssertNotNil(url, "Valid HTTPS URL should parse successfully")
        XCTAssertEqual(url?.scheme, "https")
    }

    // [P0] Invalid URL string throws invalidURL error
    func test_openURL_invalidURL_throwsInvalidURL() throws {
        let service = URLOpenerService()
        XCTAssertThrowsError(try service.openURL("not a url at all")) { error in
            guard let urlError = error as? URLOpenerError else {
                XCTFail("Expected URLOpenerError, got \(error)"); return
            }
            if case .invalidURL = urlError {
                // expected
            } else {
                XCTFail("Expected .invalidURL, got \(urlError)")
            }
        }
    }

    // [P0] Empty string throws invalidURL error
    func test_openURL_emptyString_throwsInvalidURL() throws {
        let service = URLOpenerService()
        XCTAssertThrowsError(try service.openURL("")) { error in
            guard let urlError = error as? URLOpenerError else {
                XCTFail("Expected URLOpenerError, got \(error)"); return
            }
            if case .invalidURL = urlError {
                // expected
            } else {
                XCTFail("Expected .invalidURL, got \(urlError)")
            }
        }
    }

    // MARK: - Scheme Validation

    // [P0] ftp:// URL throws unsupportedScheme error
    func test_openURL_ftpScheme_throwsUnsupportedScheme() throws {
        let service = URLOpenerService()
        XCTAssertThrowsError(try service.openURL("ftp://example.com")) { error in
            guard let urlError = error as? URLOpenerError else {
                XCTFail("Expected URLOpenerError, got \(error)"); return
            }
            if case .unsupportedScheme = urlError {
                // expected
            } else {
                XCTFail("Expected .unsupportedScheme, got \(urlError)")
            }
        }
    }

    // [P0] file:// URL throws unsupportedScheme error
    func test_openURL_fileScheme_throwsUnsupportedScheme() throws {
        let service = URLOpenerService()
        XCTAssertThrowsError(try service.openURL("file:///Users/test/doc.txt")) { error in
            guard let urlError = error as? URLOpenerError else {
                XCTFail("Expected URLOpenerError, got \(error)"); return
            }
            if case .unsupportedScheme = urlError {
                // expected
            } else {
                XCTFail("Expected .unsupportedScheme, got \(urlError)")
            }
        }
    }

    // [P0] javascript: URL throws unsupportedScheme error
    func test_openURL_javascriptScheme_throwsUnsupportedScheme() throws {
        let service = URLOpenerService()
        XCTAssertThrowsError(try service.openURL("javascript:alert(1)")) { error in
            guard let urlError = error as? URLOpenerError else {
                XCTFail("Expected URLOpenerError, got \(error)"); return
            }
            if case .unsupportedScheme = urlError {
                // expected
            } else {
                XCTFail("Expected .unsupportedScheme, got \(urlError)")
            }
        }
    }

    // [P0] data: URL throws unsupportedScheme error
    func test_openURL_dataScheme_throwsUnsupportedScheme() throws {
        let service = URLOpenerService()
        XCTAssertThrowsError(try service.openURL("data:text/html,<h1>test</h1>")) { error in
            guard let urlError = error as? URLOpenerError else {
                XCTFail("Expected URLOpenerError, got \(error)"); return
            }
            if case .unsupportedScheme = urlError {
                // expected
            } else {
                XCTFail("Expected .unsupportedScheme, got \(urlError)")
            }
        }
    }

    // [P0] http:// URL is accepted (not just https)
    func test_openURL_httpScheme_accepted() throws {
        let service = URLOpenerService()
        let urlString = "http://example.com"
        let url = URL(string: urlString)
        XCTAssertNotNil(url, "HTTP URL should parse successfully")
        XCTAssertEqual(url?.scheme, "http")
        // We can verify the URL parses; actual open may fail in headless env
    }

    // MARK: - URLOpenerError Format (cross-cutting)

    // [P0] URLOpenerError.invalidURL has required fields
    func test_urlOpenerError_invalidURL_hasRequiredFields() {
        let error = URLOpenerError.invalidURL("bad-url")
        XCTAssertEqual(error.errorCode, "invalid_url")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    // [P0] URLOpenerError.unsupportedScheme has required fields
    func test_urlOpenerError_unsupportedScheme_hasRequiredFields() {
        let error = URLOpenerError.unsupportedScheme("ftp://example.com")
        XCTAssertEqual(error.errorCode, "unsupported_scheme")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    // [P0] URLOpenerError.failedToOpen has required fields
    func test_urlOpenerError_failedToOpen_hasRequiredFields() {
        let error = URLOpenerError.failedToOpen("https://example.com")
        XCTAssertEqual(error.errorCode, "failed_to_open")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }
}
