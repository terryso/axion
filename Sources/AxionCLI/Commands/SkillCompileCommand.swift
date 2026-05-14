import ArgumentParser
import AxionCore
import Foundation

struct SkillCompileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compile",
        abstract: "将录制编译为可复用技能"
    )

    @Argument(help: "录制名称")
    var name: String

    @Option(name: .long, help: "手动指定参数名（可重复）")
    var param: [String] = []

    mutating func run() async throws {
        let safeName = RecordCommand.sanitizeFileName(name)

        // Load recording file
        let recordingsDir = RecordCommand.recordingsDirectory()
        let recordingPath = (recordingsDir as NSString).appendingPathComponent("\(safeName).json")

        guard FileManager.default.fileExists(atPath: recordingPath) else {
            throw ValidationError("录制文件不存在: \(recordingPath)")
        }

        let recordingData = try Data(contentsOf: URL(fileURLWithPath: recordingPath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let recording: Recording
        do {
            recording = try decoder.decode(Recording.self, from: recordingData)
        } catch {
            throw ValidationError("无法解析录制文件: \(error.localizedDescription)")
        }

        // Compile
        let compiler = RecordingCompiler()
        let result = compiler.compile(recording: recording, paramNames: param)

        // Save skill file
        let skillsDir = Self.skillsDirectory()
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let skillPath = (skillsDir as NSString).appendingPathComponent("\(safeName).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let skillData = try encoder.encode(result.skill)
        try skillData.write(to: URL(fileURLWithPath: skillPath))

        // Print summary
        print("[axion] 技能已编译: \(skillPath)")
        print("[axion] 步骤数: \(result.skill.steps.count)")
        if result.detectedParameterCount > 0 {
            print("[axion] 检测到的参数: \(result.skill.parameters.map(\.name).joined(separator: ", "))")
        }
        if result.optimizedStepCount > 0 {
            print("[axion] 优化移除的冗余步骤: \(result.optimizedStepCount)")
        }
    }

    static func skillsDirectory() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return (homeDir as NSString).appendingPathComponent(".axion/skills")
    }
}
