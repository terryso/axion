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
        // Load recording file
        let recordingPath = resolveFilePath(name: name, in: ConfigManager.recordingsDirectory)

        guard FileManager.default.fileExists(atPath: recordingPath) else {
            throw ValidationError("录制文件不存在: \(recordingPath)")
        }
        guard let recording = loadDecodableFile(recordingPath, as: Recording.self, decoder: axionPersistentDecoder) else {
            throw ValidationError("无法解析录制文件")
        }

        // Compile
        let compiler = RecordingCompiler()
        let result = compiler.compile(recording: recording, paramNames: param)

        // Save skill file
        let skillsDir = ConfigManager.skillsDirectory
        try FileManager.default.createDirectory(atPath: skillsDir, withIntermediateDirectories: true)

        let skillPath = resolveFilePath(name: name, in: skillsDir)
        let skillData = try axionPersistentEncoder.encode(result.skill)
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
}
