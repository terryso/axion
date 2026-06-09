import Foundation

// MARK: - JSON Parsing Helpers

/// Parses a JSON object dictionary from a String, returning nil if the string
/// is not valid JSON or the top-level value is not a `[String: Any]`.
/// Centralizes the repeated `data(using: .utf8)` + `JSONSerialization.jsonObject` pattern
/// that was duplicated across 17 call sites in 10 files.
func parseJSONDict(from string: String) -> [String: Any]? {
    guard let data = string.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return json
}

// MARK: - Duration Helpers

/// Converts a ContinuousClock.Duration to whole milliseconds.
/// Centralizes the repeated `Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)`
/// calculation that was duplicated across 9+ call sites.
func durationToMs(_ duration: ContinuousClock.Duration) -> Int {
    Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
}

// MARK: - Date Formatters

/// Shared ISO8601 date formatter with fractional seconds, used across the AxionCLI module.
/// Avoids duplicating the same formatter configuration across multiple files.
nonisolated(unsafe) let axionISO8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

/// Shared ISO8601 date formatter with default format (no fractional seconds).
/// Used by GatewaySessionStore, TraceEventHandler, RunLockService for timestamp generation.
nonisolated(unsafe) let axionISO8601BasicFormatter = ISO8601DateFormatter()

/// Shared DateFormatter for human-readable timestamps ("yyyy-MM-dd HH:mm").
/// Used by SessionResumeManager, SessionsCommand, SkillListCommand for table display.
let axionDateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f
}()

/// Shared DateFormatter for human-readable timestamps with seconds ("yyyy-MM-dd HH:mm:ss").
/// Used by CuratorCommand for status display.
let axionDateTimeSecondsFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

/// Shared DateFormatter for run ID date component ("yyyyMMdd").
/// Used by RunOrchestrator.generateRunId() for the YYYYMMDD-{6random} format.
let axionRunIdDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyyMMdd"
    return f
}()

// MARK: - JSON Array Parsing

/// Parses an array of JSON-encoded strings from a JSON dictionary payload.
/// Extracts the string array under `key`, decodes each string as type `T`, and returns the results.
/// Centralizes the repeated parseJSONDict → extract [String] → compactMap decode pattern.
func parseJSONEncodedArray<T: Decodable>(from result: String, key: String) -> [T] {
    guard let json = parseJSONDict(from: result),
          let strings = json[key] as? [String] else {
        return []
    }
    let decoder = JSONDecoder()
    return strings.compactMap { string in
        guard let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}
