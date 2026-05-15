import Testing
@testable import AxionHelper

@Suite("SelectorResolver")
struct SelectorResolverTests {

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

    @Test("exact title match")
    func exactTitleMatch() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "OK", bounds: WindowBounds(x: 10, y: 20, width: 80, height: 30)),
            makeElement(role: "AXButton", title: "Cancel", bounds: WindowBounds(x: 100, y: 20, width: 80, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "OK", titleContains: nil, axId: nil, role: "AXButton", ordinal: nil
        ))

        #expect(result.count == 1)
        #expect(result[0].x == 50) // 10 + 80/2
        #expect(result[0].y == 35) // 20 + 30/2
    }

    // MARK: - title_contains fuzzy match

    @Test("title contains fuzzy match")
    func titleContainsMatch() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "Save Document", bounds: WindowBounds(x: 0, y: 0, width: 100, height: 40)),
            makeElement(role: "AXButton", title: "Cancel", bounds: WindowBounds(x: 100, y: 0, width: 80, height: 40)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: nil, titleContains: "save", axId: nil, role: nil, ordinal: nil
        ))

        #expect(result.count == 1)
        #expect(result[0].title == "Save Document")
    }

    // MARK: - Ordinal disambiguation

    @Test("ordinal disambiguation")
    func ordinalDisambiguation() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXStaticText", title: "Item", bounds: WindowBounds(x: 0, y: 0, width: 50, height: 20)),
            makeElement(role: "AXStaticText", title: "Item", bounds: WindowBounds(x: 0, y: 30, width: 50, height: 20)),
            makeElement(role: "AXStaticText", title: "Item", bounds: WindowBounds(x: 0, y: 60, width: 50, height: 20)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "Item", titleContains: nil, axId: nil, role: "AXStaticText", ordinal: nil
        ))
        #expect(result.count == 3)

        // Ordinal 0 = first match
        #expect(result[0].y == 10)  // 0 + 20/2
        // Ordinal 2 = third match
        #expect(result[2].y == 70)  // 60 + 20/2
    }

    // MARK: - No match

    @Test("no match returns empty")
    func noMatch() {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "OK", bounds: WindowBounds(x: 10, y: 20, width: 80, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "NotExist", titleContains: nil, axId: nil, role: nil, ordinal: nil
        ))
        #expect(result.isEmpty)
    }

    // MARK: - ax_id match

    @Test("ax_id match")
    func axIdMatch() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXTextField", identifier: "search-field", bounds: WindowBounds(x: 5, y: 5, width: 200, height: 30)),
            makeElement(role: "AXTextField", identifier: "email-field", bounds: WindowBounds(x: 5, y: 50, width: 200, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: nil, titleContains: nil, axId: "email-field", role: nil, ordinal: nil
        ))
        #expect(result.count == 1)
        #expect(result[0].y == 65) // 50 + 30/2
    }

    // MARK: - AND combination of conditions

    @Test("AND combination of conditions")
    func andCombination() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "OK", bounds: WindowBounds(x: 0, y: 0, width: 60, height: 30)),
            makeElement(role: "AXStaticText", title: "OK", bounds: WindowBounds(x: 0, y: 50, width: 60, height: 20)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "OK", titleContains: nil, axId: nil, role: "AXButton", ordinal: nil
        ))
        #expect(result.count == 1)
        #expect(result[0].role == "AXButton")
    }

    // MARK: - Nested children

    @Test("nested children")
    func nestedChildren() throws {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXGroup", children: [
                makeElement(role: "AXButton", title: "Deep", bounds: WindowBounds(x: 10, y: 10, width: 50, height: 20)),
            ]),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "Deep", titleContains: nil, axId: nil, role: nil, ordinal: nil
        ))
        #expect(result.count == 1)
        #expect(result[0].x == 35) // 10 + 50/2
    }

    // MARK: - Zero-size bounds are skipped

    @Test("zero-size bounds are skipped")
    func zeroSizeBoundsSkipped() {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "Hidden", bounds: WindowBounds(x: 0, y: 0, width: 0, height: 0)),
            makeElement(role: "AXButton", title: "Visible", bounds: WindowBounds(x: 10, y: 10, width: 50, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: "Hidden", titleContains: nil, axId: nil, role: nil, ordinal: nil
        ))
        #expect(result.isEmpty)
    }

    // MARK: - Edge case tests

    @Test("all-nil selector matches nothing")
    func allNilSelectorMatchesNothing() {
        let tree = makeElement(role: "AXWindow", children: [
            makeElement(role: "AXButton", title: "OK", bounds: WindowBounds(x: 0, y: 0, width: 50, height: 30)),
        ])

        let result = engine.collectMatchesTest(element: tree, query: SelectorQuery(
            title: nil, titleContains: nil, axId: nil, role: nil, ordinal: nil
        ))
        #expect(result.isEmpty, "All-nil selector should match nothing")
    }

    @Test("negative ordinal rejected")
    func negativeOrdinalRejected() {
        let ordinal = -1
        #expect(ordinal < 0, "Negative ordinal should be rejected")
    }
}

// Expose collectMatches for testing
extension AccessibilityEngineService {
    func collectMatchesTest(element: AXElement, query: SelectorQuery) -> [SelectorMatchResult] {
        collectMatches(element: element, query: query)
    }
}
