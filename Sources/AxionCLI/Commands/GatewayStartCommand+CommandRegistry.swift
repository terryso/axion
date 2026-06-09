import OpenAgentSDK

// MARK: - Command Registry Builder

extension GatewayStartCommand {
    static func buildCommandRegistry(
        runner: GatewayRunner,
        skillRegistry: SkillRegistry,
        taskSerialQueue: TaskSerialQueue
    ) -> TGCommandRegistry {
        let statusProvider: @Sendable () async -> GatewayRunnerStatus = { [runner] in await runner.getStatus() }
        let skillsProvider: @Sendable () -> [OpenAgentSDK.Skill] = { [skillRegistry] in skillRegistry.userInvocableSkills }
        let clearSession: @Sendable (Int64) async -> Void = { [taskSerialQueue] chatId in
            await taskSerialQueue.clearSession(chatId: chatId)
        }

        let helpDef = TGCommandDef(name: "help", description: "入门指南", helpText: "", menuPriority: 1) { _ in
            TGCommandResult(text: "Axion 是一个桌面自动化助手。\n\n直接发送文本即可执行任务。\n\n可用命令:\n/commands — 查看所有命令\n/status — 查看网关状态\n/skills — 查看技能列表\n/new — 开始新会话\n/queue — 查看任务队列\n/stop — 停止当前任务", markup: nil)
        }
        let commandsDescription = "查看所有命令"
        let statusDef = TGCommandDef(name: "status", description: "查看网关状态", helpText: "", menuPriority: 3) { _ in
            TGCommandResult(text: await Self.formatStatus(statusProvider: statusProvider, skillsProvider: skillsProvider), markup: nil)
        }
        let skillsDef = TGCommandDef(name: "skills", description: "查看技能列表", helpText: "", menuPriority: 4) { _ in
            Self.formatSkills(skillsProvider: skillsProvider)
        }
        let newDef = TGCommandDef(name: "new", description: "开始新会话", helpText: "", menuPriority: 5) { chatId in
            await clearSession(chatId)
            return TGCommandResult(text: "新会话已开始", markup: nil)
        }
        let queueDef = TGCommandDef(name: "queue", description: "查看任务队列", helpText: "", menuPriority: 6) { chatId in
            let processing = await taskSerialQueue.isProcessing(chatId: chatId)
            let pending = await taskSerialQueue.pendingCount(chatId: chatId)
            let hasSession = await taskSerialQueue.hasActiveSession(chatId: chatId)
            var lines = ["📋 任务队列:"]
            lines.append("执行中: \(processing ? "是" : "否")")
            lines.append("排队中: \(pending)")
            lines.append("会话: \(hasSession ? "活跃" : "无")")
            return TGCommandResult(text: lines.joined(separator: "\n"), markup: nil)
        }
        let stopDef = TGCommandDef(name: "stop", description: "停止当前任务", helpText: "", menuPriority: 7) { chatId in
            let cancelled = await taskSerialQueue.cancelCurrentTask(chatId: chatId)
            if cancelled {
                return TGCommandResult(text: "⏹ 正在停止当前任务...", markup: nil)
            } else {
                return TGCommandResult(text: "没有正在执行的任务", markup: nil)
            }
        }

        // Build /commands handler from the other command defs (avoids hardcoding)
        let coreDefs = [helpDef, statusDef, skillsDef, newDef, queueDef, stopDef]
        let commandsDef = TGCommandDef(name: "commands", description: commandsDescription, helpText: "", menuPriority: 2) { _ in
            var lines = ["📋 可用命令:"]
            for cmd in coreDefs {
                lines.append("  /\(cmd.name) — \(cmd.description)")
            }
            lines.append("  /commands — \(commandsDescription)")
            return TGCommandResult(text: lines.joined(separator: "\n"), markup: nil)
        }

        return TGCommandRegistry(commands: [helpDef, commandsDef, statusDef, skillsDef, newDef, queueDef, stopDef])
    }

    private static func formatStatus(
        statusProvider: @Sendable () async -> GatewayRunnerStatus,
        skillsProvider: @Sendable () -> [OpenAgentSDK.Skill]
    ) async -> String {
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

    private static func formatSkills(
        skillsProvider: @Sendable () -> [OpenAgentSDK.Skill]
    ) -> TGCommandResult {
        let skills = skillsProvider().sorted { $0.name < $1.name }
        guard !skills.isEmpty else { return TGCommandResult(text: "暂无可用技能", markup: nil) }

        let pageSize = 20
        let totalPages = max(1, (skills.count + pageSize - 1) / pageSize)
        let keyboard = TelegramAdapter.buildSkillsKeyboard(skills: skills, page: 0, pageSize: pageSize)
        let text = "📋 技能列表 (1/\(totalPages))"

        return TGCommandResult(text: text, markup: keyboard)
    }
}
