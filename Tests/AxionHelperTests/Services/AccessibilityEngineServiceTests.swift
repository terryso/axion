import Testing
@testable import AxionHelper

@Suite("AccessibilityEngineService")
struct AccessibilityEngineServiceTests {

    // MARK: - AccessibilityEngineError Format

    @Test("windowNotFound error has required fields")
    func errorWindowNotFoundHasRequiredFields() {
        let error = AccessibilityEngineError.windowNotFound(windowId: 42)
        #expect(error.errorCode == "window_not_found")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("42"))
        #expect(!error.suggestion.isEmpty)
    }

    @Test("axPermissionDenied error has required fields")
    func errorAxPermissionDeniedHasRequiredFields() {
        let error = AccessibilityEngineError.axPermissionDenied
        #expect(error.errorCode == "ax_permission_denied")
        #expect(error.errorDescription != nil)
        #expect(!error.suggestion.isEmpty)
    }

    @Test("axTreeBuildFailed error has required fields")
    func errorAxTreeBuildFailedHasRequiredFields() {
        let error = AccessibilityEngineError.axTreeBuildFailed(reason: "no windows")
        #expect(error.errorCode == "ax_tree_build_failed")
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription!.contains("no windows"))
        #expect(!error.suggestion.isEmpty)
    }

    // MARK: - Error Codes

    @Test("all error codes are distinct")
    func errorCodesAllDistinct() {
        let codes = [
            AccessibilityEngineError.windowNotFound(windowId: 1).errorCode,
            AccessibilityEngineError.axPermissionDenied.errorCode,
            AccessibilityEngineError.axTreeBuildFailed(reason: "").errorCode,
        ]
        #expect(Set(codes).count == codes.count, "All error codes should be distinct")
    }

    // MARK: - Suggestions

    @Test("suggestions contain actionable guidance")
    func suggestionsContainActionableGuidance() {
        #expect(AccessibilityEngineError.windowNotFound(windowId: 1).suggestion.contains("list_windows"))
        #expect(AccessibilityEngineError.axPermissionDenied.suggestion.contains("Accessibility"))
        #expect(AccessibilityEngineError.axTreeBuildFailed(reason: "").suggestion.contains("responsive"))
    }

    // MARK: - Protocol Conformance

    @Test("conforms to WindowManaging protocol")
    func conformsToWindowManaging() {
        let service = AccessibilityEngineService()
        #expect(service is WindowManaging,
               "AccessibilityEngineService should conform to WindowManaging protocol")
    }
}
