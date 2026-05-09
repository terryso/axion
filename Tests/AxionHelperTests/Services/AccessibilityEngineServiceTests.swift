import XCTest
@testable import AxionHelper

final class AccessibilityEngineServiceTests: XCTestCase {

    // MARK: - AccessibilityEngineError Format

    func test_error_windowNotFound_hasRequiredFields() {
        let error = AccessibilityEngineError.windowNotFound(windowId: 42)
        XCTAssertEqual(error.errorCode, "window_not_found")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("42"))
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    func test_error_axPermissionDenied_hasRequiredFields() {
        let error = AccessibilityEngineError.axPermissionDenied
        XCTAssertEqual(error.errorCode, "ax_permission_denied")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    func test_error_axTreeBuildFailed_hasRequiredFields() {
        let error = AccessibilityEngineError.axTreeBuildFailed(reason: "no windows")
        XCTAssertEqual(error.errorCode, "ax_tree_build_failed")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("no windows"))
        XCTAssertFalse(error.suggestion.isEmpty)
    }

    // MARK: - Error Codes

    func test_errorCodes_allDistinct() {
        let codes = [
            AccessibilityEngineError.windowNotFound(windowId: 1).errorCode,
            AccessibilityEngineError.axPermissionDenied.errorCode,
            AccessibilityEngineError.axTreeBuildFailed(reason: "").errorCode,
        ]
        XCTAssertEqual(Set(codes).count, codes.count, "All error codes should be distinct")
    }

    // MARK: - Suggestions

    func test_suggestions_containActionableGuidance() {
        XCTAssertTrue(AccessibilityEngineError.windowNotFound(windowId: 1).suggestion.contains("list_windows"))
        XCTAssertTrue(AccessibilityEngineError.axPermissionDenied.suggestion.contains("Accessibility"))
        XCTAssertTrue(AccessibilityEngineError.axTreeBuildFailed(reason: "").suggestion.contains("responsive"))
    }

    // MARK: - Protocol Conformance

    func test_accessibilityEngineService_conformsToWindowManaging() {
        let service = AccessibilityEngineService()
        XCTAssertTrue(service is WindowManaging,
                      "AccessibilityEngineService should conform to WindowManaging protocol")
    }
}
