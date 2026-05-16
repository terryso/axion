import Foundation

/// Context of the frontmost window when an event was recorded.
public struct WindowContext: Codable, Equatable, Sendable {
    public let appName: String
    public let pid: Int32
    public let windowId: Int
    public let windowTitle: String

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case pid, windowId = "window_id", windowTitle = "window_title"
    }

    public init(appName: String, pid: Int32, windowId: Int, windowTitle: String) {
        self.appName = appName
        self.pid = pid
        self.windowId = windowId
        self.windowTitle = windowTitle
    }
}

/// A single recorded event captured during a recording session.
public struct RecordedEvent: Codable, Equatable, Sendable {
    public enum EventType: String, Codable, Sendable {
        case click
        case typeText = "type_text"
        case hotkey
        case appSwitch = "app_switch"
        case scroll
        case error
    }

    public let type: EventType
    public let timestamp: TimeInterval
    public let parameters: [String: JSONValue]
    public let windowContext: WindowContext?

    enum CodingKeys: String, CodingKey {
        case type, timestamp, parameters
        case windowContext = "window_context"
    }

    public init(type: EventType, timestamp: TimeInterval, parameters: [String: JSONValue], windowContext: WindowContext?) {
        self.type = type
        self.timestamp = timestamp
        self.parameters = parameters
        self.windowContext = windowContext
    }
}

/// A JSON value type for flexible event parameters.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// A window snapshot captured during recording for playback context.
public struct WindowSnapshot: Codable, Equatable, Sendable {
    public let windowId: Int
    public let appName: String
    public let title: String
    public let bounds: WindowBounds
    public let capturedAtEventIndex: Int

    enum CodingKeys: String, CodingKey {
        case windowId = "window_id", appName = "app_name", title, bounds
        case capturedAtEventIndex = "captured_at_event_index"
    }

    public init(windowId: Int, appName: String, title: String, bounds: WindowBounds, capturedAtEventIndex: Int) {
        self.windowId = windowId
        self.appName = appName
        self.title = title
        self.bounds = bounds
        self.capturedAtEventIndex = capturedAtEventIndex
    }
}

/// Bounds for a window snapshot.
public struct WindowBounds: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A complete recording session containing captured events and metadata.
public struct Recording: Codable, Equatable, Sendable {
    public let name: String
    public let createdAt: Date
    public let durationSeconds: TimeInterval
    public let events: [RecordedEvent]
    public let windowSnapshots: [WindowSnapshot]

    enum CodingKeys: String, CodingKey {
        case name
        case createdAt = "created_at"
        case durationSeconds = "duration_seconds"
        case events
        case windowSnapshots = "window_snapshots"
    }

    public init(name: String, createdAt: Date, durationSeconds: TimeInterval, events: [RecordedEvent], windowSnapshots: [WindowSnapshot]) {
        self.name = name
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.events = events
        self.windowSnapshots = windowSnapshots
    }
}
