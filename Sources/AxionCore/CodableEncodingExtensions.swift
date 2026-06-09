
// MARK: - Null-Encoding Helpers

/// Extension on KeyedEncodingContainer that encodes nil optional values as explicit JSON null
/// (vs `encodeIfPresent` which omits nil keys entirely from the output).
extension KeyedEncodingContainer {
    /// Encodes an optional value, writing JSON `null` when the value is nil.
    ///
    /// Use this when downstream consumers (APIs, tests) expect nil fields to appear as
    /// explicit `"key": null` rather than being omitted from the JSON object.
    public mutating func encodeNullIfNil<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
