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

    // MARK: - Deeply Nested Tree

    func testCodableRoundTrip_deeplyNested() throws {
        let leaf = AXElement(role: "AXTextField", title: nil, value: "input", bounds: nil, children: [])
        let mid = AXElement(role: "AXGroup", title: "Mid", value: nil, bounds: WindowBounds(x: 0, y: 0, width: 100, height: 50), children: [leaf])
        let root = AXElement(role: "AXWindow", title: "Root", value: nil, bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600), children: [mid])

        let data = try JSONEncoder().encode(root)
        let decoded = try JSONDecoder().decode(AXElement.self, from: data)
        XCTAssertEqual(decoded, root)
        XCTAssertEqual(decoded.children.count, 1)
        XCTAssertEqual(decoded.children[0].children.count, 1)
        XCTAssertEqual(decoded.children[0].children[0].value, "input")
    }

    // MARK: - JSON Structure

    func testJsonStructure_allFields() throws {
        let element = AXElement(
            role: "AXButton",
            title: "OK",
            value: "confirm",
            bounds: WindowBounds(x: 10, y: 20, width: 100, height: 40),
            children: []
        )
        let data = try JSONEncoder().encode(element)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["role"] as? String, "AXButton")
        XCTAssertEqual(json["title"] as? String, "OK")
        XCTAssertEqual(json["value"] as? String, "confirm")
        XCTAssertNotNil(json["bounds"])
        XCTAssertEqual((json["children"] as? [Any])?.count, 0)
    }

    func testJsonStructure_optionalFieldsOmitted() throws {
        let element = AXElement(role: "AXUnknown", title: nil, value: nil, bounds: nil, children: [])
        let data = try JSONEncoder().encode(element)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["role"] as? String, "AXUnknown")
        XCTAssertNil(json["title"])
        XCTAssertNil(json["value"])
        XCTAssertNil(json["bounds"])
    }

    // MARK: - Equality Edge Cases

    func testEquality_differentRoles() {
        let a = AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
        let b = AXElement(role: "AXCheckBox", title: "OK", value: nil, bounds: nil, children: [])
        XCTAssertNotEqual(a, b)
    }

    func testEquality_differentValues() {
        let a = AXElement(role: "AXTextField", title: nil, value: "a", bounds: nil, children: [])
        let b = AXElement(role: "AXTextField", title: nil, value: "b", bounds: nil, children: [])
        XCTAssertNotEqual(a, b)
    }

    func testEquality_differentChildren() {
        let child = AXElement(role: "AXStaticText", title: "Label", value: nil, bounds: nil, children: [])
        let a = AXElement(role: "AXGroup", title: nil, value: nil, bounds: nil, children: [])
        let b = AXElement(role: "AXGroup", title: nil, value: nil, bounds: nil, children: [child])
        XCTAssertNotEqual(a, b)
    }
}
