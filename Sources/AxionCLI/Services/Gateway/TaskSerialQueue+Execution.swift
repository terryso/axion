import Foundation
import OpenAgentSDK
import AxionCore

// MARK: - Execution Pipeline

extension TaskSerialQueue {

    private struct TaskTimeoutError: Error {}

    // MARK: - Factory Helpers

    /// Creates the BuildConfig for gateway task execution.
    /// Deduplicates identical BuildConfig construction between executeNewWithTimeout and executeWithTimeout.
    func makeBuildConfig(for pending: PendingTask) -> AgentBuilder.BuildConfig {
        let request = OpenAgentSDK.CreateRunRequest(task: pending.task)
        // Story 39.4: telegram 入口接入保守存储审批门（预留字段 + 不执行有副作用操作）。
        // 非 storage 工具由门放行（等价 bypassPermissions 语义）；storage execute 走预留+取消。
        let telegramCanUseTool = StorageApprovalGate.makeCanUseTool(
            collector: TelegramApprovalReserve(),
            surface: .telegram
        )
        return AgentBuilder.BuildConfig(
            config: config,
            task: pending.task,
            noMemory: false,
            noSkills: false,
            includePlaywright: false,
            allowForeground: request.allowForeground ?? false,
            maxSteps: request.maxSteps,
            maxTokens: nil,
            verbose: false,
            dryrun: false,
            fast: false,
            runId: nil,
            sessionId: nil,
            sessionStore: nil,
            emitTokenStream: true,
            mode: .desktopAutomation,
            permissionMode: .bypassPermissions,
            canUseTool: telegramCanUseTool,
            jsonOutput: false
        )
    }

    func makeStreamingConfig() -> TGStreamingConfig {
        TGStreamingConfig(
            typingEnabled: config.tgTypingEnabled,
            typingInterval: config.tgTypingInterval
        )
    }

    func makeGatewayRunOverrides() -> AxionRuntime.RunOverrides {
        AxionRuntime.RunOverrides(
            json: false,
            noVisualDelta: false,
            noReview: handlerProfile.noReview,
            onReviewCompleted: nil,
            reviewDataContext: handlerProfile.reviewDataContext,
            nonInteractivePause: true,
            registerResumeHandle: { [weak self] pendingId, handle in
                await self?.registerResumeHandle(pendingId: pendingId, handle: handle)
            }
        )
    }

    // MARK: - Execute & Finalize

    func executeAndFinalize(pending: PendingTask, timeoutMinutes: Double) async {
        do {
            let result: AxionRunResult
            if pending.shouldResume, let sessionId = pending.existingSessionId {
                result = try await executeWithTimeout(
                    timeoutMinutes: timeoutMinutes,
                    pending: pending,
                    sessionId: sessionId
                )
            } else {
                result = try await executeNewWithTimeout(
                    timeoutMinutes: timeoutMinutes,
                    pending: pending
                )
            }
            updateSession(from: result, chatId: pending.chatId)
            if let store = gatewaySessionStore {
                await store.recordSessionId(chatId: pending.chatId, sessionId: result.sessionId)
            }
        } catch is TaskTimeoutError {
            _ = await replyHandler(pending.chatId, "任务超时已取消 (\(Int(timeoutMinutes)) 分钟)")
        } catch is CancellationError {
            _ = await replyHandler(pending.chatId, "⏹ 任务已停止")
        } catch {
            _ = await replyHandler(pending.chatId, "任务执行失败: \(error.localizedDescription)")
        }
        activeResumeHandles.removeAll()
        currentChatId = nil
        currentExecutionTask = nil
        await runner.taskFinished()
    }

    // MARK: - Shared Execution Helpers

    /// Creates a TGEventHandler with standard gateway closures for the given pending task.
    private func makeTGEventHandler(for pending: PendingTask, streamingConfig: TGStreamingConfig) -> TGEventHandler {
        TGEventHandler(
            chatId: pending.chatId,
            allowedUserId: pending.userId,
            sendMessage: { [weak self] message, chatId in
                await self?.replyHandler(chatId, message)
            },
            editMessage: { [weak self] chatId, messageId, text in
                await self?.editHandler(chatId, messageId, text) ?? false
            },
            sendChatAction: { [weak self] chatId, action in
                await self?.chatActionHandler(chatId, action)
            },
            originalTask: pending.task,
            deferFinalDelivery: true,
            streamingConfig: streamingConfig,
            sessionStore: self.sessionStore,
            sendMessageWithMarkup: { [weak self] chatId, text, markup in
                await self?.sendMessageWithMarkupHandler(chatId, text, markup)
            }
        )
    }

    /// Runs a task with timeout protection using a task group.
    /// All actor-isolated setup (TGEventHandler, BuildConfig, handlers) is resolved
    /// before entering the task group to avoid Sendable isolation issues.
    /// The `execute` closure performs the actual runtime call (new or resume).
    private func runWithTimeout(
        timeoutMinutes: Double,
        pending: PendingTask,
        execute: @Sendable @escaping (AgentBuilder.BuildConfig, TGEventHandler, [any EventHandler]) async throws -> AxionRunResult
    ) async throws -> AxionRunResult {
        let streamingConfig = makeStreamingConfig()
        let buildConfig = makeBuildConfig(for: pending)
        let tgHandler = makeTGEventHandler(for: pending, streamingConfig: streamingConfig)
        let allHandlers: [any EventHandler] = [tgHandler] + extraHandlers
        return try await withThrowingTaskGroup(of: AxionRunResult.self) { group in
            group.addTask {
                let result = try await execute(buildConfig, tgHandler, allHandlers)
                await tgHandler.finishRun(responseText: result.responseText)
                return result
            }
            group.addTask {
                try await _Concurrency.Task.sleep(nanoseconds: UInt64(timeoutMinutes * 60 * 1_000_000_000))
                throw TaskTimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - New Task Execution

    private func executeNewWithTimeout(
        timeoutMinutes: Double,
        pending: PendingTask
    ) async throws -> AxionRunResult {
        try await runWithTimeout(timeoutMinutes: timeoutMinutes, pending: pending) { buildConfig, _, allHandlers in
            try await self.runtimeManager.executeRun(
                task: pending.task,
                buildConfig: buildConfig,
                eventBus: EventBus(),
                runOverrides: self.makeGatewayRunOverrides(),
                handlerProfile: self.handlerProfile,
                extraHandlers: allHandlers,
                sessionId: nil,
                chatId: pending.chatId,
                shouldReviewMemory: pending.shouldReviewMemory,
                shouldReviewSkills: false
            )
        }
    }

    // MARK: - Resume Task Execution

    private func executeWithTimeout(
        timeoutMinutes: Double,
        pending: PendingTask,
        sessionId: String
    ) async throws -> AxionRunResult {
        do {
            return try await runWithTimeout(timeoutMinutes: timeoutMinutes, pending: pending) { buildConfig, _, allHandlers in
                try await self.runtimeManager.resumeRun(
                    sessionId: sessionId,
                    task: pending.task,
                    buildConfig: buildConfig,
                    eventBus: EventBus(),
                    runOverrides: self.makeGatewayRunOverrides(),
                    handlerProfile: self.handlerProfile,
                    extraHandlers: allHandlers,
                    chatId: pending.chatId,
                    shouldReviewMemory: pending.shouldReviewMemory,
                    shouldReviewSkills: false
                )
            }
        } catch {
            if error is TaskTimeoutError { throw error }
            fputs("[axion] resumeSession failed for \(sessionId), degrading to new session: \(error.localizedDescription)\n", stderr)
            chatSessions.removeValue(forKey: pending.chatId)
            return try await executeNewWithTimeout(timeoutMinutes: timeoutMinutes, pending: pending)
        }
    }
}
