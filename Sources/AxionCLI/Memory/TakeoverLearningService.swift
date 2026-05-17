import ArgumentParser
import Foundation

/// Outcome of a takeover event — determines memory kind and confidence.
enum TakeoverOutcome: String, Codable, Sendable, ExpressibleByArgument {
    case success
    case failed
    case cancelled
}

/// Records takeover experiences as ``AppMemoryFact`` entries.
///
/// When a user manually takes over and the task succeeds, an *affordance* fact
/// is created (the workaround is worth trying again). If the task ultimately
/// fails, an *avoid* fact is created instead.
struct TakeoverLearningService {

    let factStore: MemoryFactStore
    let lifecycleService: MemoryLifecycleService

    // MARK: - Recording

    /// Record a takeover learning as an `AppMemoryFact`.
    ///
    /// Failures are logged but never rethrown — takeover learning must not block
    /// task execution (AC7).
    func recordTakeoverLearning(
        bundleId: String,
        appName: String? = nil,
        task: String? = nil,
        issue: String,
        summary: String,
        outcome: TakeoverOutcome = .success,
        reasonType: String? = nil,
        feedback: String? = nil
    ) async {
        do {
            let isSuccess = (outcome == .success)

            let kind: MemoryKind = isSuccess ? .affordance : .avoid
            let confidence: Double = isSuccess ? 0.72 : 0.66
            let cause: String = isSuccess ? "takeover_demonstration" : "takeover_unresolved"

            let description: String
            if isSuccess {
                description = "当被 \(issue) 阻塞时，用户手动 \(summary) 成功"
            } else {
                description = "当被 \(issue) 阻塞时，\(summary) 未解决问题"
            }

            var evidence: [String] = []
            if let task, !task.isEmpty { evidence.append("task: \(task)") }
            if !issue.isEmpty { evidence.append("issue: \(issue)") }
            if let reasonType, !reasonType.isEmpty { evidence.append("reason_type: \(reasonType)") }
            evidence.append("outcome: \(outcome.rawValue)")
            evidence.append("takeover: \(summary)")
            if let feedback, !feedback.isEmpty { evidence.append("feedback: \(feedback)") }

            let newFact = AppMemoryFact.create(
                domain: bundleId,
                kind: kind,
                description: description,
                confidence: confidence,
                scope: "user takeover",
                cause: cause,
                evidence: evidence
            )

            let existing = try await factStore.query(domain: bundleId)
            let result = lifecycleService.addFact(newFact, mergingWith: existing)
            try await factStore.save(domain: bundleId, fact: result)
        } catch {
            fputs("[axion] warning: takeover learning record failed: \(error.localizedDescription)\n", stderr)
        }
    }
}
