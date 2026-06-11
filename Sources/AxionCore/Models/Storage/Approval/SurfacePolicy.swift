import Foundation

/// Surface 策略（AC #3）。run/chat 全开放；telegram 保守（仅 scan_only/trash，禁 typed / 禁高危数据 / 禁显式确认项）。
public struct SurfacePolicy: Equatable, Sendable {

    /// 所属入口。
    public let surface: StorageSurface
    /// 允许的动作集合。
    public let allowedActions: Set<StorageAction>
    /// 是否允许 typed 确认（远程 MVP 不允许）。
    public let allowsTypedConfirmation: Bool
    /// 是否允许高危数据项（远程 MVP 不允许）。
    public let allowsHighDataRisk: Bool

    /// 按入口构造策略。
    public static func `for`(_ surface: StorageSurface) -> SurfacePolicy {
        switch surface {
        case .run, .chat:
            return SurfacePolicy(
                surface: surface,
                allowedActions: [.move, .trash, .createDirectory, .uninstallApp, .scanOnly],
                allowsTypedConfirmation: true,
                allowsHighDataRisk: true
            )
        case .telegram:
            // 保守远程策略：只读/可恢复动作，不接受 typed、不批高危数据。
            return SurfacePolicy(
                surface: surface,
                allowedActions: [.scanOnly, .trash],
                allowsTypedConfirmation: false,
                allowsHighDataRisk: false
            )
        }
    }

    /// 单项是否可在「远程语义」下被批准。
    ///
    /// - 本地入口（run/chat）：动作在白名单内即放行（所有动作均在白名单，含需 typed 的高危项）。
    /// - 远程入口（telegram）：动作受限、且剔除需显式确认 / 高危数据项。
    public func isRemotelyApprovable(item: StorageApprovalItem) -> Bool {
        guard allowedActions.contains(item.action) else { return false }
        switch surface {
        case .run, .chat:
            return true
        case .telegram:
            if item.requiresExplicitApproval { return false }
            if let dr = item.dataRisk {
                if dr == .high || dr == .forbidden { return false }
            }
            return true
        }
    }

    /// 从可批准集中剔除禁止项（远程 surface 主要使用者）。
    public func offerable(items: [StorageApprovalItem]) -> [StorageApprovalItem] {
        items.filter { isRemotelyApprovable(item: $0) }
    }

    /// 便捷静态入口：按 surface 给出可批准项。
    public static func offerable(items: [StorageApprovalItem], for surface: StorageSurface) -> [StorageApprovalItem] {
        SurfacePolicy.for(surface).offerable(items: items)
    }
}
