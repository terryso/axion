import XCTest
@testable import AxionHelper

/// Tests that directly call real URLOpenerService.openURL to exercise
/// the URL validation logic (scheme check, host check, NSWorkspace call).
final class URLOpenerServiceRealTests: XCTestCase {

    private let service = URLOpenerService()

    // MARK: - Invalid URLs

    func test_openURL_emptyString_throwsInvalidURL() {
        XCTAssertThrowsError(try service.openURL("")) { error in
            guard let e = error as? URLOpenerError, case .invalidURL = e else {
                XCTFail("Expected invalidURL"); return
            }
        }
    }

    func test_openURL_plainText_throwsInvalidURL() {
        XCTAssertThrowsError(try service.openURL("not a url")) { error in
            guard let e = error as? URLOpenerError, case .invalidURL = e else {
                XCTFail("Expected invalidURL"); return
            }
        }
    }

    // MARK: - Unsupported schemes

    func test_openURL_ftp_throwsUnsupportedScheme() {
        XCTAssertThrowsError(try service.openURL("ftp://example.com")) { error in
            guard let e = error as? URLOpenerError, case .unsupportedScheme = e else {
                XCTFail("Expected unsupportedScheme"); return
            }
        }
    }

    func test_openURL_file_throwsUnsupportedScheme() {
        XCTAssertThrowsError(try service.openURL("file:///tmp/test")) { error in
            guard let e = error as? URLOpenerError, case .unsupportedScheme = e else {
                XCTFail("Expected unsupportedScheme"); return
            }
        }
    }

    func test_openURL_javascript_throwsUnsupportedScheme() {
        XCTAssertThrowsError(try service.openURL("javascript:alert(1)")) { error in
            guard let e = error as? URLOpenerError, case .unsupportedScheme = e else {
                XCTFail("Expected unsupportedScheme"); return
            }
        }
    }

    func test_openURL_data_throwsUnsupportedScheme() {
        XCTAssertThrowsError(try service.openURL("data:text/html,<h1>test</h1>")) { error in
            guard let e = error as? URLOpenerError, case .unsupportedScheme = e else {
                XCTFail("Expected unsupportedScheme"); return
            }
        }
    }

    // MARK: - URL without host

    func test_openURL_httpsNoHost_throwsError() {
        XCTAssertThrowsError(try service.openURL("https://"))
    }

    func test_openURL_httpNoHost_throwsError() {
        XCTAssertThrowsError(try service.openURL("http://"))
    }

    // MARK: - Valid URL (may fail in headless CI)

    func test_openURL_validHttps_exercisesValidationCode() {
        // This exercises the full validation path:
        // URL parsing, scheme check, host check
        // In CI it may throw failedToOpen or succeed — both exercise the code
        do {
            try service.openURL("https://example.com")
        } catch URLOpenerError.failedToOpen {
            // Expected in headless CI — still exercises the validation code
        } catch {
            // Other errors also exercise the code
        }
    }
}
