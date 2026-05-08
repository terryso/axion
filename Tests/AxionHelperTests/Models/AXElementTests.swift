import XCTest
@testable import AxionHelper

final class AXElementTests: XCTestCase {

    func testCodableRoundTrip_leaf() throws {
        let original = AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AXElement.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTrip_withChildren() throws {
        let original = AXElement(
            role: "AXGroup",
            title: "Container",
            value: "some value",
            bounds: WindowBounds(x: 10, y: 20, width: 100, height: 50),
            children: [
                AXElement(role: "AXStaticText", title: "Label", value: nil, bounds: nil, children: []),
                AXElement(role: "AXTextField", title: nil, value: "input", bounds: nil, children: [])
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AXElement.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEquality() {
        let a = AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
        let b = AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
        let c = AXElement(role: "AXButton", title: "Cancel", value: nil, bounds: nil, children: [])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
