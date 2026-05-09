import XCTest
@testable import AxionCore

final class ValueTests: XCTestCase {

    // MARK: - Equality

    func test_equality_sameStringValues() {
        XCTAssertEqual(Value.string("hello"), Value.string("hello"))
    }

    func test_equality_differentStringValues() {
        XCTAssertNotEqual(Value.string("a"), Value.string("b"))
    }

    func test_equality_sameIntValues() {
        XCTAssertEqual(Value.int(42), Value.int(42))
    }

    func test_equality_differentIntValues() {
        XCTAssertNotEqual(Value.int(1), Value.int(2))
    }

    func test_equality_sameBoolValues() {
        XCTAssertEqual(Value.bool(true), Value.bool(true))
    }

    func test_equality_differentBoolValues() {
        XCTAssertNotEqual(Value.bool(true), Value.bool(false))
    }

    func test_equality_samePlaceholderValues() {
        XCTAssertEqual(Value.placeholder("$x"), Value.placeholder("$x"))
    }

    func test_equality_differentPlaceholderValues() {
        XCTAssertNotEqual(Value.placeholder("$x"), Value.placeholder("$y"))
    }

    func test_equality_differentCases() {
        XCTAssertNotEqual(Value.string("42"), Value.int(42))
        XCTAssertNotEqual(Value.int(1), Value.bool(true))
        XCTAssertNotEqual(Value.string("x"), Value.placeholder("x"))
    }

    // MARK: - Encoding JSON Structure

    func test_encode_string_producesTypeValue() throws {
        let value = Value.string("hello")
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "string")
        XCTAssertEqual(json["value"] as? String, "hello")
    }

    func test_encode_int_producesTypeValue() throws {
        let value = Value.int(42)
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "int")
        XCTAssertEqual(json["value"] as? Int, 42)
    }

    func test_encode_bool_producesTypeValue() throws {
        let value = Value.bool(true)
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "bool")
        XCTAssertEqual(json["value"] as? Bool, true)
    }

    func test_encode_placeholder_producesTypeValue() throws {
        let value = Value.placeholder("$window_id")
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "placeholder")
        XCTAssertEqual(json["value"] as? String, "$window_id")
    }

    // MARK: - Decoding Errors

    func test_decode_unknownType_throwsError() throws {
        let json = """
        {"type": "unknown_type", "value": "x"}
        """
        let data = Data(json.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Value.self, from: data))
    }

    // MARK: - Edge Cases

    func test_string_emptyValue_roundTrips() throws {
        let value = Value.string("")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_int_zero_roundTrips() throws {
        let value = Value.int(0)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_int_negative_roundTrips() throws {
        let value = Value.int(-100)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_int_largeValue_roundTrips() throws {
        let value = Value.int(Int.max)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_bool_false_roundTrips() throws {
        let value = Value.bool(false)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_placeholder_emptyString_roundTrips() throws {
        let value = Value.placeholder("")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_string_withSpecialCharacters_roundTrips() throws {
        let value = Value.string("hello\nworld\t\"quoted\"")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func test_string_withUnicode_roundTrips() throws {
        let value = Value.string("你好世界 🌍")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        XCTAssertEqual(decoded, value)
    }
}
