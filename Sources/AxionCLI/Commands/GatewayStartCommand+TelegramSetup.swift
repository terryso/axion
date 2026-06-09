import Foundation
import OpenAgentSDK

import AxionCore

// MARK: - Telegram Adapter Setup

extension GatewayStartCommand {
    /// Creates and wires the Telegram adapter, task queue, and callbacks.
    func setupTelegramAdapter(
        config: AxionConfig,
        infra: ServerInfrastructure,
        runtimeManager: any DaemonRuntimeManaging,
        runner: GatewayRunner,
        reviewScheduler: ReviewScheduler,
        curatorScheduler: CuratorScheduler?,
        gatewaySessionStore: GatewaySessionStore,
        gatewayProfile: HandlerProfile
    ) async {
        guard let tgToken = config.telegramBotToken else {
            fputs("[axion] Telegram bot token not configured, adapter disabled\n", stderr)
            await runner.setStatusProviders(
                tgStatus: { "disabled" },
                reviewStatus: { [weak reviewScheduler] in reviewScheduler?.lastReviewAtValue },
                reviewSummary: { [weak reviewScheduler] in reviewScheduler?.lastReviewSummaryValue },
                curatorStatus: { [weak curatorScheduler] in curatorScheduler?.lastCuratorAtValue }
            )
            return
        }

        let allowedUsersStr = config.telegramAllowedUsers ?? ""
        let allowedUsers = Set(allowedUsersStr.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        })

        let tgClient = TGAPIClient(token: tgToken)

        let sessionStore = TGInteractiveSessionStore()

        let taskSerialQueue = TaskSerialQueue(
            runtimeManager: runtimeManager,
            config: config,
            runner: runner,
            extraHandlers: [reviewScheduler] + (curatorScheduler.map { [$0] } ?? []),
            handlerProfile: gatewayProfile,
            gatewaySessionStore: gatewaySessionStore,
            replyHandler: { (chatId: Int64, message: String) -> Int64? in
                // Adapter not yet created; will be wired below
                return nil
            },
            editHandler: { (chatId: Int64, messageId: Int64, text: String) -> Bool in
                // Adapter not yet created; will be wired below
                return false
            },
            chatActionHandler: { (chatId: Int64, action: String) in
                // Adapter not yet created; will be wired below
            },
            sessionStore: sessionStore
        )

        let registry = Self.buildCommandRegistry(
            runner: runner,
            skillRegistry: infra.skillRegistry,
            taskSerialQueue: taskSerialQueue
        )
        let commandRouter = TGCommandRouter(
            registry: registry,
            skillNameChecker: { [infra] name in infra.skillRegistry.userInvocableSkills.contains { TGCommandRegistry.normalize($0.name) == name } }
        )

        let adapter = TelegramAdapter(apiClient: tgClient, allowedUsers: allowedUsers, taskQueue: taskSerialQueue, commandRouter: commandRouter, sessionStore: sessionStore, skillsProvider: { [infra] in infra.skillRegistry.userInvocableSkills })

        // Re-wire replyHandler to use the now-created adapter
        await taskSerialQueue.updateReplyHandler({ [weak adapter] chatId, message in
            guard let adapter else { return nil }
            return await adapter.sendFormatted(message, to: chatId)
        })

        // Re-wire editHandler to use the now-created adapter
        await taskSerialQueue.updateEditHandler({ [weak adapter] chatId, messageId, text in
            guard let adapter else { return false }
            return await adapter.editMessage(chatId: chatId, messageId: messageId, text: text)
        })

        // Re-wire chatActionHandler to use the now-created adapter
        await taskSerialQueue.updateChatActionHandler({ [weak adapter] chatId, action in
            await adapter?.sendChatAction(chatId: chatId, action: action)
        })

        // Re-wire sendMessageWithMarkupHandler to use the now-created adapter
        await taskSerialQueue.updateSendMessageWithMarkupHandler({ [weak adapter] chatId, text, markup in
            guard let adapter else { return nil }
            return await adapter.sendWithMarkup(text, to: chatId, replyMarkup: markup)
        })

        await adapter.setTaskQueue(taskSerialQueue)
        await runner.setTaskSerialQueue(taskSerialQueue)
        await runner.setTelegramAdapter(adapter)

        await runner.setStatusProviders(
            tgStatus: { [weak adapter] in adapter?.statusValue },
            reviewStatus: { [weak reviewScheduler] in reviewScheduler?.lastReviewAtValue },
            reviewSummary: { [weak reviewScheduler] in reviewScheduler?.lastReviewSummaryValue },
            curatorStatus: { [weak curatorScheduler] in curatorScheduler?.lastCuratorAtValue }
        )

        // Wire curator result callback for TG push
        let tgChatIds: [Int64] = allowedUsers.compactMap { Int64($0) }
        let notifyCuratorResults = config.gatewayNotifyCuratorResults ?? false
        if notifyCuratorResults {
            await curatorScheduler?.setOnCuratorResult { [weak adapter] info in
                guard info.success else {
                    for chatId in tgChatIds {
                        await adapter?.sendReply("⚠️ 后台策展失败: \(info.error ?? "unknown error")", to: chatId)
                    }
                    return
                }
                guard info.consolidations > 0 || info.prunings > 0 else { return }
                var parts: [String] = []
                if info.consolidations > 0 {
                    parts.append("合并 \(info.consolidations) 个技能")
                }
                if info.prunings > 0 {
                    parts.append("归档 \(info.prunings) 个技能")
                }
                let message = "🔧 策展完成: \(parts.joined(separator: ", "))"
                for chatId in tgChatIds {
                    await adapter?.sendReply(message, to: chatId)
                }
            }
        }

        // Wire review result callback: the per-request EventBus is stopped before
        // the detached review task completes, so we use a direct callback instead.
        await reviewScheduler.setOnReviewResult { [weak adapter] event in
            guard event.success else {
                for chatId in tgChatIds {
                    await adapter?.sendReply("⚠️ 后台审查失败", to: chatId)
                }
                return
            }
            guard !event.memoryChanges.isEmpty || !event.skillChanges.isEmpty else { return }
            var parts: [String] = []
            if !event.memoryChanges.isEmpty {
                parts.append("新增 \(event.memoryChanges.count) 条记忆")
            }
            if !event.skillChanges.isEmpty {
                parts.append("更新 \(event.skillChanges.count) 个技能")
            }
            let message = "📊 审查完成: \(parts.joined(separator: ", "))"
            for chatId in tgChatIds {
                await adapter?.sendReply(message, to: chatId)
            }
        }

        _Concurrency.Task {
            await taskSerialQueue.startProcessing()
        }
        // Sync bot menu before starting the poll loop (start() blocks until stopped)
        let menuCommands = registry.menuCommands()
        _Concurrency.Task {
            do {
                try await tgClient.setMyCommands(commands: menuCommands)
                fputs("[axion] Telegram bot menu synced (\(menuCommands.count) commands)\n", stderr)
            } catch {
                fputs("[axion] Telegram setMyCommands failed: \(error.localizedDescription)\n", stderr)
            }
        }
        _Concurrency.Task {
            await adapter.start()
        }
        fputs("[axion] Telegram adapter starting\n", stderr)
    }
}
