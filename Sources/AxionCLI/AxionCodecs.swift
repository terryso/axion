import Foundation

// MARK: - Shared JSONDecoders

/// Shared decoder with ISO8601 date strategy. Used for decoding persistent storage
/// (facts, skills, recordings) where dates were encoded with .iso8601 strategy.
/// Matches the date format produced by `axionPersistentEncoder`.
let axionPersistentDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

// MARK: - Shared JSONEncoders

/// Shared encoder with sorted keys only. Used for API responses and compact JSON output.
let axionSortedEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()

/// Shared encoder with sorted keys and pretty printing. Used for human-readable config and session files.
let axionPrettyEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    return encoder
}()

/// Shared encoder with sorted keys, pretty printing, and ISO8601 dates. Used for persistent storage
/// of facts, skills, and recordings where date consistency across sessions matters.
let axionPersistentEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}()
