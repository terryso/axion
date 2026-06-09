import Foundation
import OpenAgentSDK

// MARK: - Response Text Reconstruction

extension RunOrchestrator {

    /// Reconstructs the user-visible assistant body from streamed SDK messages.
    /// Mirrors `SDKTerminalOutputHandler` semantics so downstream surfaces like
    /// Telegram receive the same substantive content a terminal user saw.
    static func collectVisibleResponseText(from messages: [SDKMessage]) -> String? {
        var visibleChunks: [String] = []
        var streamBuffer = ""
        var lastFlushedText = ""
        var fallbackResultText: String?

        func appendVisibleChunk(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            visibleChunks.append(trimmed)
        }

        func flushStreamBuffer() {
            guard !streamBuffer.isEmpty else { return }
            lastFlushedText = streamBuffer
            appendVisibleChunk(streamBuffer)
            streamBuffer = ""
        }

        for message in messages {
            switch message {
            case .partialMessage(let data):
                streamBuffer += data.text

            case .assistant(let data):
                if !streamBuffer.isEmpty {
                    flushStreamBuffer()
                    let trimmed = data.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && trimmed != lastFlushedText {
                        if trimmed.hasPrefix(lastFlushedText) {
                            let extra = String(trimmed.dropFirst(lastFlushedText.count))
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if !extra.isEmpty {
                                appendVisibleChunk(extra)
                            }
                        } else {
                            appendVisibleChunk(trimmed)
                        }
                        lastFlushedText = trimmed
                    }
                } else if !data.text.isEmpty && data.text != lastFlushedText {
                    lastFlushedText = data.text
                    appendVisibleChunk(data.text)
                }

            case .result(let data):
                flushStreamBuffer()
                let trimmed = data.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    fallbackResultText = trimmed
                }

            case .toolUse, .toolResult, .system, .userMessage, .toolProgress,
                    .hookStarted, .hookProgress, .hookResponse, .taskStarted,
                    .taskProgress, .authStatus, .filesPersisted, .localCommandOutput,
                    .promptSuggestion, .toolUseSummary:
                flushStreamBuffer()
            }
        }

        flushStreamBuffer()

        let visibleText = visibleChunks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !visibleText.isEmpty {
            return visibleText
        }

        return fallbackResultText
    }

    /// Build a text content string from an AppProfile for storage as KnowledgeEntry.
    static func buildProfileContent(profile: AppProfile) -> String {
        var lines: [String] = []
        lines.append("App Profile: \(profile.domain)")
        lines.append("总运行次数: \(profile.totalRuns)")
        lines.append("成功次数: \(profile.successfulRuns)")
        lines.append("失败次数: \(profile.failedRuns)")
        lines.append("已熟悉: \(profile.isFamiliar ? "是" : "否")")

        if !profile.axCharacteristics.isEmpty {
            lines.append("AX特征: \(profile.axCharacteristics.joined(separator: ", "))")
        }

        if !profile.commonPatterns.isEmpty {
            let patternDescs = profile.commonPatterns.map { pattern in
                "\(pattern.sequence.joined(separator: " → ")) (频率:\(pattern.frequency), 成功率:\(Int(round(pattern.successRate * 100)))%)"
            }
            lines.append("高频路径: \(patternDescs.joined(separator: "; "))")
        }

        if !profile.knownFailures.isEmpty {
            let failureDescs = profile.knownFailures.map { failure in
                if let workaround = failure.workaround {
                    return "\(failure.failedAction) — \(failure.reason) (修正: \(workaround))"
                } else {
                    return "\(failure.failedAction) — \(failure.reason)"
                }
            }
            lines.append("已知失败: \(failureDescs.joined(separator: "; "))")
        }

        return lines.joined(separator: "\n")
    }
}
