import Foundation

import AxionCore

/// Surface 无关的审批收集协议（Story 39.4）。run / chat / telegram 各入口实现各自交互，
/// 归一为 `StorageApprovalResponse`；门（`StorageApprovalGate`）再调用纯决策函数
/// `StorageApprovalDecision.resolveOutcome` 得到统一结果。
///
/// 与工具级 `ApprovalDecision`（chat 权限粒度）不同轴：本协议是「计划项级」审批，
/// 决策对象是 `StorageApprovalItem` 子集，而非「是否允许调用某工具」。
///
/// 实现规约：
/// - 任何读取 / 解析 / 中断失败都应返回 `StorageApprovalResponse.cancel(...)`（安全默认），
///   不得抛出或放行。
/// - 不得执行真实副作用（不删文件、不发系统通知、不联网）；副作用统一交给 execute 工具在放行后执行。
/// - DI 闭包注入 I/O（isTTY / writeStdout / readLine 等），便于单元测试 Mock。
public protocol StorageApproving: Sendable {
    /// 收集审批决策。
    /// - Parameters:
    ///   - request: 审批请求（surface 无关，含 `planSummary` / `items` / typed 约束）。
    ///   - policy: 当前 surface 策略（远程保守等）。
    /// - Returns: 审批响应（动作 + 已批准/被拒 key + 可选 typed 载荷 / 远程预留）。
    func collect(
        request: StorageApprovalRequest,
        policy: SurfacePolicy
    ) async -> StorageApprovalResponse
}
