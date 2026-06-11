import Foundation
import OpenAgentSDK

import AxionCore

/// 存储审批门（Story 39.4）。在 execute 工具执行**之前**拦截，收集决策并归一为 `CanUseToolResult`。
///
/// 共享核心 `decide(...)`：run（`makeRunCanUseTool` 包装）与 chat（PermissionHandler 分支）都走它，
/// 保证「计划项级」决策语义在两个入口一致。纯决策由 `StorageApprovalDecision.resolveOutcome` 完成。
///
/// 安全红线：
/// - 非 storage execute 工具：run 入口 `.allow()`，chat 入口返回 nil（交回既有权限流程）。
/// - `--json` / 非 TTY：无法交互确认 → 安全默认 `.deny`。
/// - 决不永久删除（本门只做审批；删除与否由 execute 工具的 action 白名单决定，恒为 trash/move）。
enum StorageApprovalGate {

    /// 通用工厂：任意 surface 用（storage 工具走门，其余放行）。telegram 入口用此接入保守预留策略。
    static func makeCanUseTool(
        collector: StorageApproving,
        surface: StorageSurface,
        isInteractiveFn: @escaping @Sendable () -> Bool = { false },
        jsonOutput: Bool = false
    ) -> CanUseToolFn {
        return { tool, input, _ in
            if let result = await decide(
                toolName: tool.name,
                input: input,
                surface: surface,
                jsonOutput: jsonOutput,
                isInteractive: isInteractiveFn(),
                collector: collector
            ) {
                return result
            }
            return .allow()
        }
    }

    /// run 入口用：返回一个完整 `CanUseToolFn`（storage 工具走门，其余放行）。
    static func makeRunCanUseTool(
        collector: StorageApproving,
        isInteractiveFn: @escaping @Sendable () -> Bool,
        jsonOutput: Bool
    ) -> CanUseToolFn {
        return { tool, input, _ in
            if let result = await decide(
                toolName: tool.name,
                input: input,
                surface: .run,
                jsonOutput: jsonOutput,
                isInteractive: isInteractiveFn(),
                collector: collector
            ) {
                return result
            }
            // 非 storage execute 工具：一律放行（AC #7）。
            return .allow()
        }
    }

    /// 共享决策核心。返回 nil 表示「不是我的工具」，调用方应回退到默认处理。
    /// - chat 分支：`if let r = await decide(...) { return r }`，否则继续既有权限流程。
    /// - run 分支：`decide(...) ?? .allow()`。
    static func decide(
        toolName: String,
        input: Any,
        surface: StorageSurface,
        jsonOutput: Bool,
        isInteractive: Bool,
        collector: StorageApproving
    ) async -> CanUseToolResult? {
        guard toolName == "execute_storage_plan" || toolName == "execute_app_uninstall" else {
            return nil
        }
        guard let params = input as? [String: Any],
              let parsed = StorageApprovalInput.build(toolName: toolName, params: params) else {
            // 无法解析待审批项：与 executor 使用同一组解析器，executor 也会拒绝；此处直接拒绝，避免无计划放行。
            return .deny("storage_approval_denied: unparseable_input (无法解析待审批项，请按工具 schema 重新调用)")
        }

        let policy = SurfacePolicy.for(surface)
        let summary = PlanSummary.build(
            operationId: parsed.operationId,
            surface: surface,
            items: parsed.items,
            reversible: true,
            requiresTypedConfirmation: parsed.requiresTypedConfirmation
        )

        // 非 TTY / --json：无法交互确认 → 安全默认拒绝（破坏性操作执行次数为 0）。
        // 按 AC #5 / #10，在 deny 中附带结构化 PlanSummary（snake_case、Codable），
        // 经工具错误流入既有输出契约（不向 stdout 直接打印，避免污染 --json 流），
        // 供带外（out-of-band）确认通道解析消费（带外通道本身不在本 Story 范围）。
        if jsonOutput {
            return .deny("storage_approval_denied: approval_required (存储执行工具在 --json 模式下无法交互审批；请在 TTY 中去掉 --json 重试)\n" + summary.renderJSON())
        }
        // 例外：telegram surface 本身非交互（其 collector 只做预留 + 保守取消，无需 TTY）。
        if surface != .telegram, !isInteractive {
            return .deny("storage_approval_denied: approval_required (存储执行工具需在交互式 TTY 中审批)\n" + summary.renderJSON())
        }

        let request = StorageApprovalRequest(
            operationId: parsed.operationId,
            surface: surface,
            planSummary: summary,
            items: parsed.items,
            requiresTypedConfirmation: parsed.requiresTypedConfirmation,
            userRequest: parsed.userRequest,
            typedConfirmationCandidates: parsed.typedConfirmationCandidates
        )

        let response = await collector.collect(request: request, policy: policy)
        let outcome = StorageApprovalDecision.resolveOutcome(request: request, response: response, policy: policy)
        switch outcome {
        case .allow:
            return .allow()
        case .deny(let reason):
            return .deny("storage_approval_denied: \(reason)")
        case .denySubset(let set):
            return .deny(StorageApprovalDecision.renderSubsetRecall(set))
        }
    }
}
