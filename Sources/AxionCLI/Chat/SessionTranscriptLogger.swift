import Foundation

/// 会话转录日志器 — 受 Codex session_log.rs 启发。
///
/// 在交互模式中自动将每次交互（用户输入、assistant 响应、工具调用/结果、
/// 系统事件）持久化为 JSONL 文件，用于事后回顾、调试和对话重放。
///
/// **存储路径：** `~/.axion/sessions/{sessionId}.jsonl`
///
/// **格式：** 每行一个 JSON 对象，含 type/content/ts 等字段
///
/// **I/O 注入：** 所有文件操作通过闭包注入，便于单元测试。
///
/// **线程安全：** struct 为值类型，通过 `@unchecked Sendable` 标记，
/// 因为 `appendFn` 闭包由调用方确保线程安全（通常写入单个文件）。
struct SessionTranscriptLogger: Sendable {

    // MARK: - Types

    /// 转录条目类型。
    enum EntryType: String, Sendable, Equatable {
        case userInput = "user_input"
        case assistant = "assistant"
        case toolUse = "tool_use"
        case toolResult = "tool_result"
        case system = "system"
        case sessionStart = "session_start"
        case sessionEnd = "session_end"
    }

    /// 单条转录记录。
    struct Entry: Sendable, Equatable {
        let type: EntryType
        let content: String
        let ts: String
        /// 可选元数据（工具名、持续时长、token 数等）。
        let metadata: [String: String]?

        /// 渲染为 JSONL 行。
        func toJSONLine() -> String? {
            var obj: [String: Any] = [
                "type": type.rawValue,
                "content": content,
                "ts": ts,
            ]
            if let meta = metadata, !meta.isEmpty {
                obj["metadata"] = meta
            }
            guard let data = try? JSONSerialization.data(
                withJSONObject: obj,
                options: .sortedKeys
            ) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        /// 从 JSONL 行解析。
        static func fromJSONLine(_ line: String) -> Entry? {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let typeStr = obj["type"] as? String,
                  let type = EntryType(rawValue: typeStr),
                  let content = obj["content"] as? String
            else { return nil }
            let ts = obj["ts"] as? String ?? ""
            let metadata = obj["metadata"] as? [String: String]
            return Entry(type: type, content: content, ts: ts, metadata: metadata)
        }
    }

    // MARK: - I/O Closures

    /// 追加一行到文件（含换行符）。调用方负责创建目录。
    let appendFn: @Sendable (String, String) -> Void

    /// 确保目录存在。
    let ensureDirFn: @Sendable (String) -> Void

    // MARK: - Init

    /// 使用真实文件系统 I/O。
    /// - Parameter dirPath: 会话目录（`~/.axion/sessions/`）。
    static func live(dirPath: String = ConfigManager.sessionsDirectory) -> SessionTranscriptLogger {
        SessionTranscriptLogger(
            appendFn: { path, line in
                guard let data = (line + "\n").data(using: .utf8) else { return }
                let fm = FileManager.default
                if !fm.fileExists(atPath: path) {
                    fm.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
                }
                if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            },
            ensureDirFn: { dir in
                try? FileManager.default.createDirectory(
                    atPath: dir,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            }
        )
    }

    /// 使用禁用 I/O（用于不应写日志的场景）。
    static var disabled: SessionTranscriptLogger {
        SessionTranscriptLogger(
            appendFn: { _, _ in },
            ensureDirFn: { _ in }
        )
    }

    // MARK: - Public API

    /// 返回会话 JSONL 文件的完整路径。
    static func transcriptPath(sessionId: String, dirPath: String) -> String {
        return (dirPath as NSString).appendingPathComponent("\(sessionId).jsonl")
    }

    /// 打开会话：确保目录存在，写入 session_start 条目。
    func open(sessionId: String, dirPath: String, model: String, cwd: String) {
        ensureDirFn(dirPath)
        let path = Self.transcriptPath(sessionId: sessionId, dirPath: dirPath)
        let entry = Entry(
            type: .sessionStart,
            content: "session started",
            ts: nowISO(),
            metadata: ["model": model, "cwd": cwd]
        )
        append(entry: entry, filePath: path)
    }

    /// 记录用户输入。
    func logUserInput(_ text: String, sessionId: String, dirPath: String) {
        let path = Self.transcriptPath(sessionId: sessionId, dirPath: dirPath)
        let entry = Entry(type: .userInput, content: text, ts: nowISO(), metadata: nil)
        append(entry: entry, filePath: path)
    }

    /// 记录 assistant 响应。
    func logAssistant(_ text: String, sessionId: String, dirPath: String) {
        guard !text.isEmpty else { return }
        let path = Self.transcriptPath(sessionId: sessionId, dirPath: dirPath)
        let entry = Entry(type: .assistant, content: text, ts: nowISO(), metadata: nil)
        append(entry: entry, filePath: path)
    }

    /// 记录工具调用。
    func logToolUse(toolName: String, input: String, sessionId: String, dirPath: String) {
        let path = Self.transcriptPath(sessionId: sessionId, dirPath: dirPath)
        let entry = Entry(
            type: .toolUse,
            content: input,
            ts: nowISO(),
            metadata: ["tool": toolName]
        )
        append(entry: entry, filePath: path)
    }

    /// 记录工具结果。
    func logToolResult(toolName: String, content: String, isError: Bool, durationMs: Int?, sessionId: String, dirPath: String) {
        let path = Self.transcriptPath(sessionId: sessionId, dirPath: dirPath)
        var meta: [String: String] = ["tool": toolName]
        if isError { meta["error"] = "true" }
        if let dur = durationMs { meta["duration_ms"] = "\(dur)" }
        // 截断过长的工具结果（保留前 2000 字符）
        let truncated = content.count > 2000 ? String(content.prefix(2000)) + "…" : content
        let entry = Entry(type: .toolResult, content: truncated, ts: nowISO(), metadata: meta)
        append(entry: entry, filePath: path)
    }

    /// 关闭会话：写入 session_end 条目含累计统计。
    func close(sessionId: String, dirPath: String, turns: Int, totalTokens: Int, durationMs: Int) {
        let path = Self.transcriptPath(sessionId: sessionId, dirPath: dirPath)
        let entry = Entry(
            type: .sessionEnd,
            content: "session ended",
            ts: nowISO(),
            metadata: [
                "turns": "\(turns)",
                "total_tokens": "\(totalTokens)",
                "duration_ms": "\(durationMs)",
            ]
        )
        append(entry: entry, filePath: path)
    }

    // MARK: - Private

    private func append(entry: Entry, filePath: String) {
        guard let line = entry.toJSONLine() else { return }
        appendFn(filePath, line)
    }

    private func nowISO() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
