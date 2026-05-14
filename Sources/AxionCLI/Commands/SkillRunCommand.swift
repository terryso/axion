import ArgumentParser
import AxionCore
import Foundation

struct SkillRunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "执行已保存的技能"
    )

    @Argument(help: "技能名称")
    var name: String

    @Option(name: .long, help: "参数（可重复，格式 key=value）")
    var param: [String] = []

    @Flag(name: .long, help: "允许前台操作")
    var allowForeground: Bool = true

    mutating func run() async throws {
        let safeName = RecordCommand.sanitizeFileName(name)
        let skillsDir = SkillCompileCommand.skillsDirectory()
        let skillPath = (skillsDir as NSString).appendingPathComponent("\(safeName).json")

        guard FileManager.default.fileExists(atPath: skillPath) else {
            throw ValidationError("技能不存在: \(safeName)")
        }

        // Load skill
        let skillData = try Data(contentsOf: URL(fileURLWithPath: skillPath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let skill: Skill
        do {
            skill = try decoder.decode(Skill.self, from: skillData)
        } catch {
            throw ValidationError("无法解析技能文件: \(error.localizedDescription)")
        }

        // Parse --param key=value
        let paramValues = try parseParams()

        // Validate required parameters
        for param in skill.parameters where param.defaultValue == nil {
            guard paramValues[param.name] != nil else {
                throw ValidationError("缺少必需参数: \(param.name)")
            }
        }

        // Start Helper
        let helperManager = HelperProcessManager()
        print("[axion] 正在启动 Helper...")
        try await helperManager.start()

        try await withTaskCancellationHandler {
            // Create MCPClientProtocol adapter
            let client = HelperMCPClientAdapter(manager: helperManager)
            let executor = SkillExecutor(client: client)

            let result = try await executor.execute(skill: skill, paramValues: paramValues)

            await helperManager.stop()

            if result.success {
                // Update skill metadata only on success
                var updatedSkill = skill
                updatedSkill.lastUsedAt = Date()
                updatedSkill.executionCount += 1
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                encoder.dateEncodingStrategy = .iso8601
                let updatedData = try encoder.encode(updatedSkill)
                try updatedData.write(to: URL(fileURLWithPath: skillPath))

                let formatted = String(format: "%.1f", result.durationSeconds)
                print("技能 '\(skill.name)' 完成。\(result.stepsExecuted) 步，耗时 \(formatted) 秒。")
            } else if let error = result.errorMessage {
                print("技能 '\(skill.name)' \(error)。建议使用 axion run 代替。")
                throw ExitCode(1)
            }
        } onCancel: {
            _Concurrency.Task {
                await helperManager.stop()
            }
        }
    }

    private func parseParams() throws -> [String: String] {
        try Self.parseParamStrings(param)
    }

    static func parseParamStrings(_ strings: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        for p in strings {
            guard let eqIndex = p.firstIndex(of: "=") else {
                throw ValidationError("参数格式错误: \(p)。正确格式: key=value")
            }
            let key = String(p[..<eqIndex])
            let value = String(p[p.index(after: eqIndex)...])
            guard !key.isEmpty else {
                throw ValidationError("参数名不能为空: \(p)")
            }
            result[key] = value
        }
        return result
    }
}

struct HelperMCPClientAdapter: MCPClientProtocol {
    let manager: HelperProcessManager

    func callTool(name: String, arguments: [String: Value]) async throws -> String {
        try await manager.callTool(name: name, arguments: arguments)
    }

    func listTools() async throws -> [String] {
        try await manager.listTools()
    }
}
