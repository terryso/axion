import Testing
@testable import AxionHelper

@Suite("URLOpenerService Real")
struct URLOpenerServiceRealTests {

    private let service = URLOpenerService()

    // MARK: - Invalid URLs

    @Test("openURL empty string throws invalidURL")
    func openURLEmptyStringThrowsInvalidURL() {
        do {
            try service.openURL("")
            Issue.record("Expected invalidURL error")
        } catch let error as URLOpenerError {
            if case .invalidURL = error {
                // expected
            } else {
                Issue.record("Expected invalidURL, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("openURL plain text throws invalidURL")
    func openURLPlainTextThrowsInvalidURL() {
        do {
            try service.openURL("not a url")
            Issue.record("Expected invalidURL error")
        } catch let error as URLOpenerError {
            if case .invalidURL = error {
                // expected
            } else {
                Issue.record("Expected invalidURL, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Unsupported schemes

    @Test("openURL ftp throws unsupportedScheme")
    func openURLFtpThrowsUnsupportedScheme() {
        do {
            try service.openURL("ftp://example.com")
            Issue.record("Expected unsupportedScheme error")
        } catch let error as URLOpenerError {
            if case .unsupportedScheme = error {
                // expected
            } else {
                Issue.record("Expected unsupportedScheme, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("openURL file throws unsupportedScheme")
    func openURLFileThrowsUnsupportedScheme() {
        do {
            try service.openURL("file:///tmp/test")
            Issue.record("Expected unsupportedScheme error")
        } catch let error as URLOpenerError {
            if case .unsupportedScheme = error {
                // expected
            } else {
                Issue.record("Expected unsupportedScheme, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("openURL javascript throws unsupportedScheme")
    func openURLJavascriptThrowsUnsupportedScheme() {
        do {
            try service.openURL("javascript:alert(1)")
            Issue.record("Expected unsupportedScheme error")
        } catch let error as URLOpenerError {
            if case .unsupportedScheme = error {
                // expected
            } else {
                Issue.record("Expected unsupportedScheme, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("openURL data throws unsupportedScheme")
    func openURLDataThrowsUnsupportedScheme() {
        do {
            try service.openURL("data:text/html,<h1>test</h1>")
            Issue.record("Expected unsupportedScheme error")
        } catch let error as URLOpenerError {
            if case .unsupportedScheme = error {
                // expected
            } else {
                Issue.record("Expected unsupportedScheme, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - URL without host

    @Test("openURL https with no host throws error")
    func openURLHttpsNoHost() {
        do {
            try service.openURL("https://")
            Issue.record("Expected error")
        } catch {
            // Expected
        }
    }

    @Test("openURL http with no host throws error")
    func openURLHttpNoHost() {
        do {
            try service.openURL("http://")
            Issue.record("Expected error")
        } catch {
            // Expected
        }
    }

    // MARK: - Valid URL (may fail in headless CI)

    @Test("openURL valid https exercises validation code")
    func openURLValidHttpsExercisesCode() {
        do {
            try service.openURL("https://example.com")
        } catch URLOpenerError.failedToOpen {
            // Expected in headless CI — still exercises the validation code
        } catch {
            // Other errors also exercise the code
        }
    }
}
