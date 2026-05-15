import Foundation
import Testing
@testable import AxionHelper

@Suite("AXElement")
struct AXElementTests {

    @Test("codable round trip leaf")
    func codableRoundTripLeaf() throws {
        let original = AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AXElement.self, from: data)
        #expect(decoded == original)
    }

    @Test("codable round trip with children")
    func codableRoundTripWithChildren() throws {
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
        #expect(decoded == original)
    }

    @Test("equality")
    func equality() {
        let a = AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
        let b = AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
        let c = AXElement(role: "AXButton", title: "Cancel", value: nil, bounds: nil, children: [])
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - Deeply Nested Tree

    @Test("codable round trip deeply nested")
    func codableRoundTripDeeplyNested() throws {
        let leaf = AXElement(role: "AXTextField", title: nil, value: "input", bounds: nil, children: [])
        let mid = AXElement(role: "AXGroup", title: "Mid", value: nil, bounds: WindowBounds(x: 0, y: 0, width: 100, height: 50), children: [leaf])
        let root = AXElement(role: "AXWindow", title: "Root", value: nil, bounds: WindowBounds(x: 0, y: 0, width: 800, height: 600), children: [mid])

        let data = try JSONEncoder().encode(root)
        let decoded = try JSONDecoder().decode(AXElement.self, from: data)
        #expect(decoded == root)
        #expect(decoded.children.count == 1)
        #expect(decoded.children[0].children.count == 1)
        #expect(decoded.children[0].children[0].value == "input")
    }

    // MARK: - JSON Structure

    @Test("JSON structure with all fields")
    func jsonStructureAllFields() throws {
        let element = AXElement(
            role: "AXButton",
            title: "OK",
            value: "confirm",
            bounds: WindowBounds(x: 10, y: 20, width: 100, height: 40),
            children: []
        )
        let data = try JSONEncoder().encode(element)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["role"] as? String == "AXButton")
        #expect(json["title"] as? String == "OK")
        #expect(json["value"] as? String == "confirm")
        #expect(json["bounds"] != nil)
        #expect((json["children"] as? [Any])?.count == 0)
    }

    @Test("JSON structure with optional fields omitted")
    func jsonStructureOptionalFieldsOmitted() throws {
        let element = AXElement(role: "AXUnknown", title: nil, value: nil, bounds: nil, children: [])
        let data = try JSONEncoder().encode(element)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["role"] as? String == "AXUnknown")
        #expect(json["title"] == nil)
        #expect(json["value"] == nil)
        #expect(json["bounds"] == nil)
    }

    // MARK: - Equality Edge Cases

    @Test("equality: different roles")
    func equalityDifferentRoles() {
        let a = AXElement(role: "AXButton", title: "OK", value: nil, bounds: nil, children: [])
        let b = AXElement(role: "AXCheckBox", title: "OK", value: nil, bounds: nil, children: [])
        #expect(a != b)
    }

    @Test("equality: different values")
    func equalityDifferentValues() {
        let a = AXElement(role: "AXTextField", title: nil, value: "a", bounds: nil, children: [])
        let b = AXElement(role: "AXTextField", title: nil, value: "b", bounds: nil, children: [])
        #expect(a != b)
    }

    @Test("equality: different children")
    func equalityDifferentChildren() {
        let child = AXElement(role: "AXStaticText", title: "Label", value: nil, bounds: nil, children: [])
        let a = AXElement(role: "AXGroup", title: nil, value: nil, bounds: nil, children: [])
        let b = AXElement(role: "AXGroup", title: nil, value: nil, bounds: nil, children: [child])
        #expect(a != b)
    }
}
