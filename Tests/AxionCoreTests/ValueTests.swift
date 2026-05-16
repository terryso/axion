import Foundation
import Testing
@testable import AxionCore

@Suite("Value")
struct ValueTests {

    // MARK: - Equality

    @Test("equality same string values")
    func equalitySameStringValues() {
        #expect(Value.string("hello") == Value.string("hello"))
    }

    @Test("equality different string values")
    func equalityDifferentStringValues() {
        #expect(Value.string("a") != Value.string("b"))
    }

    @Test("equality same int values")
    func equalitySameIntValues() {
        #expect(Value.int(42) == Value.int(42))
    }

    @Test("equality different int values")
    func equalityDifferentIntValues() {
        #expect(Value.int(1) != Value.int(2))
    }

    @Test("equality same bool values")
    func equalitySameBoolValues() {
        #expect(Value.bool(true) == Value.bool(true))
    }

    @Test("equality different bool values")
    func equalityDifferentBoolValues() {
        #expect(Value.bool(true) != Value.bool(false))
    }

    @Test("equality same placeholder values")
    func equalitySamePlaceholderValues() {
        #expect(Value.placeholder("$x") == Value.placeholder("$x"))
    }

    @Test("equality different placeholder values")
    func equalityDifferentPlaceholderValues() {
        #expect(Value.placeholder("$x") != Value.placeholder("$y"))
    }

    @Test("equality different cases")
    func equalityDifferentCases() {
        #expect(Value.string("42") != Value.int(42))
        #expect(Value.int(1) != Value.bool(true))
        #expect(Value.string("x") != Value.placeholder("x"))
    }

    // MARK: - Encoding JSON Structure

    @Test("encode string produces type value")
    func encodeStringProducesTypeValue() throws {
        let value = Value.string("hello")
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "string")
        #expect(json["value"] as? String == "hello")
    }

    @Test("encode int produces type value")
    func encodeIntProducesTypeValue() throws {
        let value = Value.int(42)
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "int")
        #expect(json["value"] as? Int == 42)
    }

    @Test("encode bool produces type value")
    func encodeBoolProducesTypeValue() throws {
        let value = Value.bool(true)
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "bool")
        #expect(json["value"] as? Bool == true)
    }

    @Test("encode placeholder produces type value")
    func encodePlaceholderProducesTypeValue() throws {
        let value = Value.placeholder("$window_id")
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["type"] as? String == "placeholder")
        #expect(json["value"] as? String == "$window_id")
    }

    // MARK: - Decoding Errors

    @Test("decode unknown type throws error")
    func decodeUnknownTypeThrowsError() throws {
        let json = """
        {"type": "unknown_type", "value": "x"}
        """
        let data = Data(json.utf8)
        #expect(throws: Error.self) {
            try JSONDecoder().decode(Value.self, from: data)
        }
    }

    // MARK: - Edge Cases

    @Test("string empty value round trips")
    func stringEmptyValueRoundTrips() throws {
        let value = Value.string("")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("int zero round trips")
    func intZeroRoundTrips() throws {
        let value = Value.int(0)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("int negative round trips")
    func intNegativeRoundTrips() throws {
        let value = Value.int(-100)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("int large value round trips")
    func intLargeValueRoundTrips() throws {
        let value = Value.int(Int.max)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("bool false round trips")
    func boolFalseRoundTrips() throws {
        let value = Value.bool(false)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("placeholder empty string round trips")
    func placeholderEmptyStringRoundTrips() throws {
        let value = Value.placeholder("")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("string with special characters round trips")
    func stringWithSpecialCharactersRoundTrips() throws {
        let value = Value.string("hello\nworld\t\"quoted\"")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    @Test("string with unicode round trips")
    func stringWithUnicodeRoundTrips() throws {
        let value = Value.string("你好世界 🌍")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }
}
