import Foundation
import OpenAgentSDK

struct TGCommandRouter: Sendable {
    typealias StatusProvider = @Sendable () async -> GatewayRunnerStatus
    typealias SkillsProvider = @Sendable () -> [Skill]
    typealias ClearSession = @Sendable (Int64) -> Void

    private let statusProvider: StatusProvider
    private let skillsProvider: SkillsProvider
    private let clearSession: ClearSession?

    init(
        statusProvider: @escaping StatusProvider,
        skillsProvider: @escaping SkillsProvider,
        clearSession: ClearSession? = nil
    ) {
        self.statusProvider = statusProvider
        self.skillsProvider = skillsProvider
        self.clearSession = clearSession
    }

    /// Returns reply text for a command message, or nil if not a command.
    func handle(_ text: String, chatId: Int64) async -> String? {
        guard text.hasPrefix("/") else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let firstToken = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        let command = firstToken.split(separator: "@").first.map(String.init) ?? firstToken

        switch command {
        case "/status":
            return await formatStatus()
        case "/skills":
            return formatSkills()
        case "/new":
            clearSession?(chatId)
            return "新会话已开始"
        default:
            return "未知命令。可用命令：/status, /skills, /new"
        }
    }

    private func formatStatus() async -> String {
        let status = await statusProvider()
        let uptime = Int(status.uptimeSeconds)
        let hours = uptime / 3600
        let minutes = (uptime % 3600) / 60
        let seconds = uptime % 60

        var lines = ["📊 Gateway Status"]
        lines.append("状态: \(status.state)")
        lines.append("运行中任务: \(status.activeTaskCount)")
        if hours > 0 {
            lines.append("运行时长: \(hours)h \(minutes)m \(seconds)s")
        } else {
            lines.append("运行时长: \(minutes)m \(seconds)s")
        }
        lines.append("TG 连接: \(status.tgConnected ?? "disabled")")
        let skills = skillsProvider()
        lines.append("可用技能: \(skills.count) 个")
        return lines.joined(separator: "\n")
    }

    private func formatSkills() -> String {
        let skills = skillsProvider()
        guard !skills.isEmpty else {
            return "暂无可用技能"
        }

        var lines = ["📋 可用技能 (\(skills.count) 个):"]
        for skill in skills.sorted(by: { $0.name < $1.name }) {
            lines.append("  • \(skill.name): \(skill.description)")
        }
        return lines.joined(separator: "\n")
    }
}
