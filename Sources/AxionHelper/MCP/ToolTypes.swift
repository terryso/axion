import Foundation
import MCP
import MCPTool

// MARK: - Shared Error Payload

/// Generic error payload returned by tool implementations.
/// Kept internal — not exported beyond AxionHelper.
struct ToolErrorPayload: Codable {
    let error: String
    let message: String
    let suggestion: String
}

// MARK: - Blocking Dialog Detection (Epic 8)

/// Information about a blocking dialog detected after launching an app.
struct BlockingDialogInfo: Codable {
    let windowId: Int
    let title: String

    enum CodingKeys: String, CodingKey {
        case windowId = "window_id"
        case title
    }
}

/// Checks the window list for a topmost window that looks like a blocking
/// open/save/import dialog.
func detectBlockingDialog(windows: [WindowInfo], appPid: Int32) -> BlockingDialogInfo? {
    let candidates = windows
        .filter { $0.pid == appPid }
        .filter { $0.bounds.width >= 200 && $0.bounds.height >= 120 }
        .sorted { $0.zOrder < $1.zOrder }

    guard let top = candidates.first,
          let title = top.title?.trimmingCharacters(in: .whitespaces),
          !title.isEmpty else { return nil }

    let dialogKeywords = ["open", "save", "import", "export", "place", "choose", "select", "打开", "存储", "导入", "导出"]
    let lowerTitle = title.lowercased()
    guard dialogKeywords.contains(where: { lowerTitle.contains($0) || lowerTitle.contains($0.lowercased()) }) else { return nil }

    return BlockingDialogInfo(windowId: top.windowId, title: title)
}

// MARK: - Action Result Types

struct CoordinateActionResult: Codable {
    let success: Bool
    let action: String
    let x: Int
    let y: Int
}

struct DragActionResult: Codable {
    let success: Bool
    let action: String
    let fromX: Int
    let fromY: Int
    let toX: Int
    let toY: Int
    enum CodingKeys: String, CodingKey {
        case success, action
        case fromX = "from_x", fromY = "from_y", toX = "to_x", toY = "to_y"
    }
}

struct TextActionResult: Codable {
    let success: Bool
    let action: String
    let text: String
}

struct KeyActionResult: Codable {
    let success: Bool
    let action: String
    let key: String
}

struct HotkeyActionResult: Codable {
    let success: Bool
    let action: String
    let keys: String
}

struct ScrollActionResult: Codable {
    let success: Bool
    let action: String
    let direction: String
    let amount: Int
}

struct ScreenshotActionResult: Codable {
    let success: Bool
    let action: String
    let imageData: String

    enum CodingKeys: String, CodingKey {
        case success, action
        case imageData = "image_data"
    }
}

struct SelectorActionResult: Codable {
    let success: Bool
    let action: String
    let x: Int
    let y: Int
    let matchedRole: String?
    let matchedTitle: String?
}

struct RecordingActionResult: Codable {
    let success: Bool
    let action: String
    let message: String
}

struct StopRecordingResult: Codable {
    let success: Bool
    let action: String
    let eventCount: Int
    let events: [String]
    let windowSnapshots: [String]

    enum CodingKeys: String, CodingKey {
        case success, action
        case eventCount = "event_count"
        case events
        case windowSnapshots = "window_snapshots"
    }
}

struct WindowBoundsResult: Codable {
    let success: Bool
    let action: String
    let windowId: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    enum CodingKeys: String, CodingKey {
        case success, action
        case windowId = "window_id"
        case x, y, width, height
    }
}

struct ArrangeResult: Codable {
    let success: Bool
    let action: String
    let layout: String
    let windows: [WindowBoundsResult]
}

enum WindowLayoutKind: String, CaseIterable {
    case tileLeftRight = "tile-left-right"
    case tileTopBottom = "tile-top-bottom"
    case cascade = "cascade"
}

// MARK: - Click Target Resolution

/// Resolves click coordinates from either raw (x, y) or AX selector + window_id.
/// Shared by ClickTool, DoubleClickTool, and RightClickTool.
func resolveClickCoordinates(
    x: Int?, y: Int?,
    windowId: Int?,
    selector: SelectorQuery?
) throws -> (x: Int, y: Int) {
    if let selector {
        guard let wid = windowId else {
            throw InputSimulationError.noClickTarget(message: "window_id is required when using __selector")
        }
        let result = try ServiceContainer.shared.accessibilityEngine.resolveSelector(windowId: wid, query: selector)
        return (result.x, result.y)
    }
    guard let x, let y else {
        throw InputSimulationError.noClickTarget(message: "Provide either (x, y) coordinates or (__selector with window_id)")
    }
    return (x, y)
}

// MARK: - Click Helper Encoding

func encodeClickResult(action: String, x: Int, y: Int) -> String {
    let result = SelectorActionResult(success: true, action: action, x: x, y: y, matchedRole: nil, matchedTitle: nil)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(result)) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
}

func encodeError(_ error: InputSimulationError) -> String {
    let payload = ToolErrorPayload(error: error.errorCode, message: error.localizedDescription, suggestion: error.suggestion)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(payload)) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
}

func encodeSelectorError(_ error: AccessibilityEngineService.SelectorError) -> String {
    let payload = ToolErrorPayload(error: error.errorCode, message: error.localizedDescription, suggestion: error.suggestion)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(payload)) ?? Data()
    return String(data: data, encoding: .utf8) ?? "{}"
}
