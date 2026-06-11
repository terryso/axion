import Foundation

import AxionCore

/// chat 入口审批收集器：逐项结构化确认（`approvePlan` / `approveItem` / `cancel`）。
///
/// - 与 run 的「全计划确认」不同：chat 逐项询问，支持子集授权（部分批准）。
/// - DI 闭包注入 I/O（`writeStdout` / `readLine`），便于单元测试 Mock；不直接读写 stdin/stdout。
/// - 子集结果（`approveItem`）经 `resolveOutcome` 触发子集召回（Agent 以子集重调）。
struct ChatApprovalCollector: StorageApproving {

    let writeStdout: @Sendable (String) -> Void
    let readLine: @Sendable () -> String?
    let now: @Sendable () -> String

    init(
        writeStdout: @escaping @Sendable (String) -> Void,
        readLine: @escaping @Sendable () -> String?,
        now: @escaping @Sendable () -> String = { ISO8601DateFormatter().string(from: Date()) }
    ) {
        self.writeStdout = writeStdout
        self.readLine = readLine
        self.now = now
    }

    func collect(request: StorageApprovalRequest, policy: SurfacePolicy) async -> StorageApprovalResponse {
        writeStdout("\n" + request.planSummary.renderTerminal() + "\n")
        writeStdout("\n逐项确认：[y] 批准   [n] 跳过   [a] 批准全部剩余   [q] 取消\n")

        var approvedKeys: [String] = []
        var rejectedKeys: [String] = []
        var approveAll = false
        var cancelled = false

        for item in request.items {
            if cancelled {
                rejectedKeys.append(item.key)
                continue
            }
            if approveAll {
                approvedKeys.append(item.key)
                continue
            }
            writeStdout("\n  [\(item.action.rawValue)] \(item.sourcePath)  — \(item.reason)")
            writeStdout("\n  批准？[y/n/a/q]：")
            let raw = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch raw {
            case "y", "yes", "批准":
                approvedKeys.append(item.key)
            case "a", "all":
                approveAll = true
                approvedKeys.append(item.key)
            case "q", "cancel", "取消":
                cancelled = true
                rejectedKeys.append(item.key)
            default:  // n / no / 空 → 跳过
                rejectedKeys.append(item.key)
            }
        }

        if cancelled || approvedKeys.isEmpty {
            writeStdout("已取消（无可批准项）。\n")
            return StorageApprovalResponse.cancel(
                operationId: request.operationId,
                surface: request.surface,
                collectedAt: now()
            )
        }

        // typed 二次确认（App 卸载）。
        var typedPayload: String? = nil
        if request.requiresTypedConfirmation,
           let candidates = request.typedConfirmationCandidates,
           let hint = candidates.first, !hint.isEmpty {
            writeStdout("\n该操作将卸载 App，请输入应用名以二次确认（\(hint)）：")
            typedPayload = readLine()
        }

        let action: StorageApprovalAction = (approvedKeys.count == request.items.count) ? .approvePlan : .approveItem
        writeStdout("✓ 已批准 \(approvedKeys.count)/\(request.items.count) 项。\n")
        return StorageApprovalResponse(
            operationId: request.operationId,
            surface: request.surface,
            action: action,
            approvedItemKeys: approvedKeys,
            rejectedItemKeys: rejectedKeys,
            typedConfirmationPayload: typedPayload,
            remoteReserved: nil,
            collectedAt: now()
        )
    }
}
