import Foundation

import AxionCore

/// 把 execute 工具的入参（`[String: Any]`）归一为审批请求所需的 `StorageApprovalItem` 集合。
///
/// 复用既有静态解析器（Dev Notes「复用清单」），不重复实现解析：
/// - `ExecuteStoragePlanTool.parseItem/parseAction/parseEvidence/parseSizeBytes`
/// - `ExecuteAppUninstallTool.parseApp/parseSupportItem`
///
/// 工具入参 schema 不变（AC #2「Do Not Modify Execute Tools」）；审批拦截发生在工具执行**之前**。
struct StorageApprovalInput {

    let operationId: String
    let userRequest: String?
    let items: [StorageApprovalItem]
    let requiresTypedConfirmation: Bool
    let typedConfirmationCandidates: [String]?

    /// 由工具名 + 入参构造；非 storage execute 工具返回 nil。
    static func build(toolName: String, params: [String: Any]) -> StorageApprovalInput? {
        switch toolName {
        case "execute_storage_plan":
            return buildStoragePlan(params)
        case "execute_app_uninstall":
            return buildAppUninstall(params)
        default:
            return nil
        }
    }

    // MARK: - execute_storage_plan

    private static func buildStoragePlan(_ params: [String: Any]) -> StorageApprovalInput? {
        let operationId = (params["operation_id"] as? String) ?? ""
        let userRequest = (params["user_request"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let rawItems = params["items"] as? [[String: Any]], !rawItems.isEmpty else { return nil }
        let items: [StorageApprovalItem] = rawItems.compactMap { raw in
            guard let parsed = ExecuteStoragePlanTool.parseItem(raw) else { return nil }
            // execute_storage_plan 的 item 不携带 risk/data_risk：move/trash/create_directory 均为低风险可恢复，
            // 默认 riskLevel=.low、requiresExplicitApproval=false。
            return StorageApprovalItem(
                key: parsed.source,
                action: parsed.action,
                sourcePath: parsed.source,
                targetPath: parsed.target,
                sizeBytes: parsed.sizeBytes,
                riskLevel: .low,
                dataRisk: nil,
                reason: parsed.reason ?? "",
                requiresExplicitApproval: false,
                evidence: parsed.evidence
            )
        }
        guard !items.isEmpty else { return nil }
        return StorageApprovalInput(
            operationId: operationId,
            userRequest: userRequest,
            items: items,
            requiresTypedConfirmation: false,
            typedConfirmationCandidates: nil
        )
    }

    // MARK: - execute_app_uninstall

    private static func buildAppUninstall(_ params: [String: Any]) -> StorageApprovalInput? {
        guard let rawApp = params["app"] as? [String: Any],
              let app = ExecuteAppUninstallTool.parseApp(rawApp) else { return nil }
        let operationId = (params["operation_id"] as? String) ?? ""
        let userRequest = (params["user_request"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let uninstallBundle = params["uninstall_bundle"] as? Bool ?? false
        let supportItems = (params["support_data_items"] as? [[String: Any]])?
            .compactMap { ExecuteAppUninstallTool.parseSupportItem($0) } ?? []

        var items: [StorageApprovalItem] = []
        if uninstallBundle {
            // App bundle 卸载：高风险、需显式确认、需 typed。
            items.append(StorageApprovalItem(
                key: app.bundlePath,
                action: .uninstallApp,
                sourcePath: app.bundlePath,
                targetPath: nil,
                sizeBytes: app.sizeBytes,
                riskLevel: .high,
                dataRisk: .medium,
                reason: "卸载 App bundle：\(app.displayName.isEmpty ? app.bundleIdentifier : app.displayName)",
                requiresExplicitApproval: true,
                evidence: nil
            ))
        }
        for s in supportItems {
            items.append(StorageApprovalItem(
                key: s.path,
                action: .trash,
                sourcePath: s.path,
                targetPath: nil,
                sizeBytes: s.sizeBytes,
                riskLevel: riskLevel(forDataRisk: s.dataRisk),
                dataRisk: s.dataRisk,
                reason: "清理 support 数据（\(s.category.rawValue)）",
                requiresExplicitApproval: s.requiresExplicitApproval,
                evidence: s.matchEvidence
            ))
        }
        guard !items.isEmpty else { return nil }

        // 卸载 bundle 时强制 typed 确认（候选 = 显示名 / bundleId）。
        let requiresTyped = uninstallBundle
        let candidates: [String]? = uninstallBundle
            ? [app.displayName, app.bundleIdentifier].filter { !$0.isEmpty }
            : nil
        return StorageApprovalInput(
            operationId: operationId,
            userRequest: userRequest,
            items: items,
            requiresTypedConfirmation: requiresTyped,
            typedConfirmationCandidates: candidates
        )
    }

    /// 由 `DataRisk` 推导展示用 `RiskLevel`（forbidden 视作 high，后续仍会被 policy/executor 拒绝）。
    private static func riskLevel(forDataRisk dataRisk: DataRisk) -> RiskLevel {
        switch dataRisk {
        case .low: return .low
        case .medium: return .medium
        case .high, .forbidden: return .high
        }
    }
}
