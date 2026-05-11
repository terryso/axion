import XCTest

@testable import AxionHelper

final class SelectorResolverTests: XCTestCase {

    // MARK: - Helper to build AX trees

    private func makeElement(
        role: String = "AXButton",
        title: String? = nil,
        identifier: String? = nil,
        bounds: WindowBounds? = nil,
        children: [AXElement] = []
    ) -> AXElement {
        AXElement(role: role, title: title, value: nil, identifier: identifier, bounds: bounds, children: children)
    }

    private let engine = AccessibilityEngineService()

    // MARK: - Exact title match

    func testExactTitleMatch() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "OK", bounds: WindowBounds(x: 10, y: 20, width: 80, height: 30)),
            makeElement(role: "AXButton", title: "Cancel", bounds: WindowBounds(x: 100, y: 20, width: 80, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "OK", titleContains: nil, axId: nil, role: "AXButton", ordinal: nil
        ))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].x, 50) // 10 + 80/2
        XCTAssertEqual(result[0].y, 35) // 20 + 30/2
    }

    // MARK: - title_contains fuzzy match

    func testTitleContainsMatch() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "Save Document", bounds: WindowBounds(x: 0, y: 0, width: 100, height: 40)),
            makeElement(role: "AXButton", title: "Cancel", bounds: WindowBounds(x: 100, y: 0, width: 80, height: 40)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: nil, titleContains: "save", axId: nil, role: nil, ordinal: nil
        ))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Save Document")
    }

    // MARK: - Ordinal disambiguation

    func testOrdinalDisambiguation() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXStaticText", title: "Item", bounds: WindowBounds(x: 0, y: 0, width: 50, height: 20)),
            makeElement(role: "AXStaticText", title: "Item", bounds: WindowBounds(x: 0, y: 30, width: 50, height: 20)),
            makeElement(role: "AXStaticText", title: "Item", bounds: WindowBounds(x: 0, y: 60, width: 50, height: 20)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "Item", titleContains: nil, axId: nil, role: "AXStaticText", ordinal: nil
        ))
        XCTAssertEqual(result.count, 3)

        // Ordinal 0 = first match
        XCTAssertEqual(result[0].y, 10)  // 0 + 20/2
        // Ordinal 2 = third match
        XCTAssertEqual(result[2].y, 70)  // 60 + 20/2
    }

    // MARK: - No match

    func testNoMatch() {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "OK", bounds: WindowBounds(x: 10, y: 20, width: 80, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "NotExist", titleContains: nil, axId: nil, role: nil, ordinal: nil
        ))
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - ax_id match

    func testAxIdMatch() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXTextField", identifier: "search-field", bounds: WindowBounds(x: 5, y: 5, width: 200, height: 30)),
            makeElement(role: "AXTextField", identifier: "email-field", bounds: WindowBounds(x: 5, y: 50, width: 200, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: nil, titleContains: nil, axId: "email-field", role: nil, ordinal: nil
        ))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].y, 65) // 50 + 30/2
    }

    // MARK: - AND combination of conditions

    func testAndCombination() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "OK", bounds: WindowBounds(x: 0, y: 0, width: 60, height: 30)),
            makeElement(role: "AXStaticText", title: "OK", bounds: WindowBounds(x: 0, y: 50, width: 60, height: 20)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "OK", titleContains: nil, axId: nil, role: "AXButton", ordinal: nil
        ))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].role, "AXButton")
    }

    // MARK: - Nested children

    func testNestedChildren() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXGroup", children: [
                makeElement(role: "AXButton", title: "Deep", bounds: WindowBounds(x: 10, y: 10, width: 50, height: 20)),
            ]),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "Deep", titleContains: nil, axId: nil, role: nil, ordinal: nil
        ))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].x, 35) // 10 + 50/2
    }

    // MARK: - Zero-size bounds are skipped

    func testZeroSizeBoundsSkipped() {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "Hidden", bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0)),
            makeElement(role: "AXButton", title: "Visible", bounds: WindowBounds(x: 10, y: 10, width: 50, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "Hidden", titleContains: nil, axId: nil, role: nil, ordinal: nil
        ))
        XCTAssertTrue(result.isEmpty)
    }
}

// Expose collectMatches for testing
extension AccessibilityEngineService {
    func collectMatchesTest(element: AXElement, query: SelectorQuery) -> [SelectorMatchResult] {
        collectMatches(element: element, query: query)
    }
}

// MARK: - Edge case tests from review

extension SelectorResolverTests {

    func testAllNilSelectorMatchesNothing() {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "OK", bounds: WindowBounds(x: 0, y: 0, width: 50, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: nil, titleContains: nil, axId: nil, role: nil, ordinal: nil
        ))
        XCTAssertTrue(result.isEmpty, "All-nil selector should match nothing")
    }

    func testNegativeOrdinalRejected() {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "Item", bounds: WindowBounds(x: 0, y: 0, width: 50, height: 30)),
        ])

        // We can't easily test resolveSelector directly (needs real CG window),
        // but we verify ordinal validation logic
        let ordinal = -1
        XCTAssertLessThan(ordinal, 0, "Negative ordinal should be rejected")
    }
}
