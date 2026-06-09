import Foundation
import OpenAgentSDK

import AxionCore

// MARK: - Generic File Load/Store

/// Reads a JSON file and decodes it as the given Decodable type.
/// Returns `nil` if the file is missing or decoding fails.
/// Centralizes the repeated `FileManager.contents` + `JSONDecoder().decode` pattern
/// that was duplicated across ConfigManager, AxionRuntime, RunLockService, and API routes.
func loadDecodableFile<T: Decodable>(
    _ path: String, as type: T.Type = T.self,
    decoder: JSONDecoder = JSONDecoder()
) -> T? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return try? decoder.decode(T.self, from: data)
}

/// Persists a TrackedRun record to an "api-output.json" file in the given directory.
/// Creates a best-effort atomic write, logging failures instead of throwing.
/// Centralizes the repeated encode + atomic-write pattern from RunCoordinator and AxionRunRecovery.
func persistRunRecord(_ run: TrackedRun, toDirectory dir: String) {
    do {
        let path = (dir as NSString).appendingPathComponent("api-output.json")
        let data = try axionSortedEncoder.encode(run)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    } catch {
        print("[RunPersistence] Warning: failed to persist record for run \(run.runId): \(error)")
    }
}

// MARK: - JSONL Append Helper

/// Appends a JSON-serializable record as a single line to a JSON-lines file.
/// Creates the parent directory and/or file if they don't exist.
/// Centralizes the repeated directory-ensure + FileHandle-open/create + seek + write + close
/// pattern that was duplicated between TraceRecorder and TraceEventHandler.
func appendJSONLRecord(_ record: [String: Any], to filePath: String) {
    guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }

    let dir = (filePath as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: filePath)) else {
        try? line.appending("\n").write(toFile: filePath, atomically: true, encoding: .utf8)
        return
    }
    handle.seekToEndOfFile()
    handle.write((line + "\n").data(using: .utf8)!)
    handle.closeFile()
}

// MARK: - File Path Resolution

/// Resolves a sanitized file path for a named resource in a directory.
/// Combines `sanitizeFileName` + `appendingPathComponent` into a single call,
/// centralizing the repeated path construction pattern across skill and recording commands.
func resolveFilePath(name: String, extension ext: String = "json", in directory: String) -> String {
    let safeName = sanitizeFileName(name)
    return (directory as NSString).appendingPathComponent("\(safeName).\(ext)")
}

// MARK: - File Name Sanitization

/// Sanitizes a user-supplied name for use as a file name by stripping invalid characters,
/// trimming whitespace, and preventing directory traversal (".." / "./").
/// Centralizes the repeated sanitization that was scattered across skill and recording commands.
func sanitizeFileName(_ name: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        .union(.controlCharacters)
    let filtered = name.components(separatedBy: invalid).joined(separator: "_")
    let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
    let safe = trimmed.isEmpty ? "untitled" : trimmed
    return safe.replacingOccurrences(of: "..", with: "_")
        .replacingOccurrences(of: "./", with: "_/")
}

// MARK: - Recorded Skill Loading

/// Loads all recorded skills from JSON files in the given directory.
/// Returns `(name, skill)` tuples sorted by name, where `name` is derived from the filename
/// (without `.json` extension). Centralizes the repeated directory-list → filter → decode loop
/// that was duplicated between SkillListCommand and AxionAPI+SkillsRoutes.
func loadAllRecordedSkills(in directory: String) -> [(name: String, skill: AxionCore.Skill)] {
    let fm = FileManager.default
    guard let fileNames = try? fm.contentsOfDirectory(atPath: directory) else { return [] }

    return fileNames.filter { $0.hasSuffix(".json") }.compactMap { fileName in
        let filePath = (directory as NSString).appendingPathComponent(fileName)
        guard let data = fm.contents(atPath: filePath),
              let skill = try? axionPersistentDecoder.decode(AxionCore.Skill.self, from: data) else { return nil }
        return (name: String(fileName.dropLast(5)), skill: skill)
    }.sorted { $0.name < $1.name }
}

// MARK: - Skill Usage Tracking

/// Tracks a skill execution by incrementing its view count in the usage store.
/// Consolidates the repeated SkillUsageStore creation + bumpView + error logging pattern
/// that was duplicated across SkillRunCommand, RunOrchestrator, SkillAPIRunner, and AxionRuntime.
func trackSkillUsage(skillName: String) async {
    let usageStore = SkillUsageStore(skillsDir: ConfigManager.skillsDirectory)
    do {
        try await usageStore.bumpView(skillName: skillName)
    } catch {
        axionSkillUsageLogger.warning("Skill usage tracking failed for '\(skillName)': \(error.localizedDescription)")
    }
}
