import AxionCore
import Foundation
import OpenAgentSDK

// MARK: - Shared CLI Runtime Helpers

/// Registers CLI-mode handlers (trace, memory, review, etc.) into a runtime.
/// Used by both `RunCommand` and `ResumeCommand` to ensure consistent handler setup.
@discardableResult
func registerCLIHandlers<R: AxionRuntimeLifecycle>(
    into runtime: R,
    config: AxionConfig,
    noMemory: Bool,
    noReview: Bool,
    noVisualDelta: Bool
) async -> ReviewDataContext {
    let memoryDir = ConfigManager.memoryDirectory
    let traceDir = ConfigManager.traceDirectory
    let reviewDataContext = ReviewDataContext()

    let profile = HandlerProfile(
        context: .cli,
        config: config,
        memoryDir: memoryDir,
        traceDir: traceDir,
        noMemory: noMemory,
        noReview: noReview,
        noVisualDelta: noVisualDelta,
        reviewDataContext: reviewDataContext
    )
    for handler in profile.buildHandlers() {
        await runtime.registerHandler(handler)
    }
    return reviewDataContext
}

/// Sends a macOS desktop notification summarizing a completed run.
/// Used by both `RunCommand` and `ResumeCommand` for consistent notification formatting.
func sendRunCompletionNotification(
    result: AxionRunResult,
    message: String,
    notify: @Sendable (String, String?, String) -> Void
) {
    let elapsedSec = result.durationMs / 1000
    let numTurns = result.runCompleteContext?.numTurns ?? result.totalSteps

    let title: String
    switch result.state {
    case .completed: title = "Axion 完成"
    case .failed: title = "Axion 失败"
    default: title = "Axion"
    }

    var subtitle = "耗时 \(elapsedSec)s · \(numTurns) 次调用"
    if let cost = result.runCompleteContext?.totalCostUsd, cost > 0 {
        subtitle += " · $\(String(format: "%.4f", cost))"
    }

    notify(title, subtitle, String(message.prefix(200)))
}

/// Manages the full runtime lifecycle for CLI commands: registers handlers, starts the
/// event loop, runs the execute closure, then tears down. Used by both `RunCommand` and
/// `ResumeCommand` to ensure consistent lifecycle management.
func executeCLIWithRuntime(
    config: AxionConfig,
    json: Bool,
    noMemory: Bool,
    noReview: Bool,
    noVisualDelta: Bool,
    runtime: any AxionRuntimeLifecycle,
    execute: (AxionRuntime.RunOverrides) async throws -> AxionRunResult
) async throws -> AxionRunResult {
    let reviewDC = await registerCLIHandlers(
        into: runtime, config: config,
        noMemory: noMemory, noReview: noReview, noVisualDelta: noVisualDelta
    )

    let eventLoopTask = _Concurrency.Task { await runtime.startEventLoop() }

    let overrides = AxionRuntime.RunOverrides(
        json: json,
        noVisualDelta: noVisualDelta,
        noReview: noReview,
        onReviewCompleted: nil,
        reviewDataContext: reviewDC,
        nonInteractivePause: false, registerResumeHandle: nil
    )

    let result: AxionRunResult
    do {
        result = try await execute(overrides)
    } catch {
        eventLoopTask.cancel()
        await runtime.stopEventLoop()
        throw error
    }
    eventLoopTask.cancel()
    await runtime.stopEventLoop()

    return result
}

/// Outputs a failed run's error message in the requested format (JSON or plain text).
/// Returns `true` if the result was a failure (caller should `throw ExitCode(1)`).
func outputCLIError(_ result: AxionRunResult, json: Bool) -> Bool {
    guard result.state == .failed, let msg = result.errorMessage else { return false }
    if json {
        let obj: [String: String] = ["error": msg, "runId": result.sessionId, "status": "failed"]
        if let data = try? axionSortedEncoder.encode(obj) {
            fputs(String(data: data, encoding: .utf8) ?? "{}\n", stdout)
        }
    } else {
        fputs("[axion] 错误: \(msg)\n", stderr)
    }
    return true
}
