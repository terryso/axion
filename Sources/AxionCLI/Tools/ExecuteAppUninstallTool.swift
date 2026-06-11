import Foundation
import OpenAgentSDK

import AxionCore

/// `execute_app_uninstall` —— 执行用户**已确认**的 App 卸载（首个有副作用的 app-uninstall 工具，
/// `isReadOnly = false`）。需用户确认后才调用（typed/逐项确认强制由入口 39.4 统一）。
///
/// 安全红线：App bundle + support 数据一律 `trashItem`（系统废纸篓，可恢复），**永不永久删除**
/// （不存在 `delete` 动作）。executor 执行前写 manifest 草稿（`status = planned`），并对 bundle 做
/// 纵深校验（AC #12：路径 ∈ search_roots、非系统保护、存在且为 `.app`、bundleId 匹配）、运行中先
/// graceful 退出（AC #3）、support 项策略校验（AC #7/#8）。可经 `undo_storage_op` 撤销（AC #10）。
///
/// 入参即「已批准的执行集」——审批决策由调用方/入口在调用工具**之前**完成。
final class ExecuteAppUninstallTool: ToolProtocol, Sendable {

    let name = "execute_app_uninstall"
    let description = "执行用户已确认的 App 卸载（移 App bundle 与/或已批准的 support 数据到系统废纸篓），返回可审计的 StorageManifest。安全红线：永不永久删除（不存在 delete 动作）；bundle + support 一律 trash（可恢复）；运行中 App 先 graceful 退出，退出失败不移动；executor 独立纵深校验 bundle（必须在 search_roots 之下、非系统保护、存在且为 .app、bundleId 匹配）与 support 项（低置信度/forbidden/共享未批准拒绝）。可经 undo_storage_op 撤销。参数：operation_id(必填)、app(必填对象)、uninstall_bundle(Bool)、support_data_items(对象数组)、search_roots(必填，bundle 校验范围)、surface(默认 run)、user_request(可选)、home_directory(可选)。"
    nonisolated(unsafe) let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": [
            "operation_id": [
                "type": "string",
                "description": "Operation ID (links execution to the scan plan for audit).",
            ],
            "app": [
                "type": "object",
                "description": "Target app candidate (from scan_app_uninstall).",
                "properties": [
                    "bundle_path": ["type": "string"],
                    "bundle_identifier": ["type": "string"],
                    "display_name": ["type": "string"],
                    "version": ["type": "string"],
                    "team_identifier": ["type": "string"],
                    "size_bytes": ["type": "integer"],
                    "is_running": ["type": "boolean"],
                    "is_system_protected": ["type": "boolean"],
                    "match_confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                ],
                "required": ["bundle_path"],
            ],
            "uninstall_bundle": [
                "type": "boolean",
                "description": "Whether to trash the app bundle (false = support-data cleanup only).",
            ],
            "support_data_items": [
                "type": "array",
                "description": "Approved support data items to trash.",
                "items": [
                    "type": "object",
                    "properties": [
                        "category": ["type": "string", "enum": [
                            "cache", "logs", "http_storage", "web_kit", "preferences", "saved_state",
                            "application_scripts", "application_support", "container", "group_container",
                            "launch_agent", "forbidden",
                        ]],
                        "path": ["type": "string"],
                        "size_bytes": ["type": "integer"],
                        "match_confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                        "data_risk": ["type": "string", "enum": ["low", "medium", "high", "forbidden"]],
                        "default_selected": ["type": "boolean"],
                        "requires_explicit_approval": ["type": "boolean"],
                        "match_evidence": [
                            "type": "object",
                            "properties": [
                                "rule": ["type": "string"],
                                "source": ["type": "string"],
                                "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                            ],
                        ],
                    ],
                    "required": ["category", "path"],
                ],
            ],
            "search_roots": [
                "type": "array",
                "items": ["type": "string"],
                "description": "App discovery roots used to re-validate the bundle path is within an approved scope.",
            ],
            "surface": [
                "type": "string",
                "enum": ["run", "chat"],
                "description": "Entry surface (default run).",
            ],
            "user_request": ["type": "string", "description": "Original user task (recorded for audit)."],
            "home_directory": ["type": "string", "description": "Home directory for path expansion (default real home)."],
        ],
        "required": ["operation_id", "app", "search_roots"],
    ]
    let isReadOnly = false

    private let executor: AppUninstallExecuting
    private let config: StorageConfig

    init(executor: AppUninstallExecuting, config: StorageConfig = .default) {
        self.executor = executor
        self.config = config
    }

    func call(input: Any, context: ToolContext) async -> ToolResult {
        let toolUseId = context.toolUseId
        guard let params = input as? [String: Any] else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "invalid_input",
                message: "Input must be a JSON object",
                suggestion: "Pass a JSON object with 'operation_id', 'app', 'search_roots', and optional 'uninstall_bundle'/'support_data_items'"
            )
        }

        // operation_id：必填
        if let err = ToolResultHelper.requireStringParam(
            params: params, key: "operation_id", toolUseId: toolUseId,
            error: "missing_operation_id",
            message: "Missing required 'operation_id' parameter",
            suggestion: "Pass an operation_id (e.g. returned by scan_app_uninstall)"
        ) { return err }
        let operationId = params["operation_id"] as? String ?? ""

        // search_roots：必填且非空（bundle 纵深校验范围）
        guard let rawRoots = params["search_roots"] as? [String], !rawRoots.isEmpty else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "missing_search_roots",
                message: "Missing or empty 'search_roots' parameter",
                suggestion: "Provide 'search_roots' (the app discovery roots used by scan_app_uninstall)"
            )
        }

        // app：必填
        guard let rawApp = params["app"] as? [String: Any], let app = Self.parseApp(rawApp) else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "missing_or_invalid_app",
                message: "Missing or invalid 'app' parameter",
                suggestion: "Provide an 'app' object with a non-empty 'bundle_path'"
            )
        }

        // uninstall_bundle（默认 false）+ support_data_items（默认空）
        let uninstallBundle = params["uninstall_bundle"] as? Bool ?? false
        let supportItems = (params["support_data_items"] as? [[String: Any]])?
            .compactMap { Self.parseSupportItem($0) } ?? []

        // 至少要有 bundle 卸载或 support 项其一
        guard uninstallBundle || !supportItems.isEmpty else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "no_action_requested",
                message: "Nothing to execute: uninstall_bundle is false and support_data_items is empty",
                suggestion: "Set uninstall_bundle=true and/or provide non-empty support_data_items"
            )
        }

        let surface: StorageSurface
        switch (params["surface"] as? String) ?? "run" {
        case "chat": surface = .chat
        default: surface = .run
        }
        let userRequest = (params["user_request"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let home = (params["home_directory"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()

        let request = AppUninstallExecuteRequest(
            operationId: operationId,
            surface: surface,
            app: app,
            uninstallBundle: uninstallBundle,
            supportDataItems: supportItems,
            searchRoots: rawRoots.map { URL(fileURLWithPath: StorageExclusions.standardize($0, home: home)) },
            userRequest: userRequest,
            homeDirectory: home,
            storageOpsDir: config.storageOpsDir
        )

        let result = await executor.execute(request)

        return ToolResultHelper.encodeResult(toolUseId: toolUseId, isError: false) { encoder in
            try encoder.encode(result.manifest)
        }
    }

    // MARK: - Parsing

    static func parseApp(_ raw: [String: Any]) -> AppCandidate? {
        guard let bundlePath = raw["bundle_path"] as? String, !bundlePath.isEmpty else { return nil }
        let bundleId = raw["bundle_identifier"] as? String ?? ""
        let displayName = raw["display_name"] as? String ?? ""
        let version = raw["version"] as? String ?? ""
        let teamId = (raw["team_identifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let sizeBytes = ExecuteStoragePlanTool.parseSizeBytes(raw["size_bytes"])
        let isRunning = raw["is_running"] as? Bool ?? false
        let isSystemProtected = raw["is_system_protected"] as? Bool ?? false
        let matchConfidence = (raw["match_confidence"] as? String)
            .flatMap { AppMatchConfidence(rawValue: $0.lowercased()) } ?? .low
        return AppCandidate(
            displayName: displayName,
            bundleIdentifier: bundleId,
            bundlePath: bundlePath,
            version: version,
            teamIdentifier: teamId,
            sizeBytes: sizeBytes,
            isRunning: isRunning,
            isSystemProtected: isSystemProtected,
            matchConfidence: matchConfidence
        )
    }

    static func parseSupportItem(_ raw: [String: Any]) -> SupportDataItem? {
        guard let path = raw["path"] as? String, !path.isEmpty,
              let category = parseCategory(raw["category"]) else { return nil }
        let matchConfidence = (raw["match_confidence"] as? String)
            .flatMap { StorageConfidence(rawValue: $0.lowercased()) } ?? .medium
        let dataRisk = (raw["data_risk"] as? String)
            .flatMap { DataRisk(rawValue: $0.lowercased()) } ?? .medium
        let defaultSelected = raw["default_selected"] as? Bool ?? false
        let requiresExplicit = raw["requires_explicit_approval"] as? Bool ?? false
        let evidence = ExecuteStoragePlanTool.parseEvidence(raw["match_evidence"])
            ?? StorageEvidence(rule: "", source: "")
        let sizeBytes = ExecuteStoragePlanTool.parseSizeBytes(raw["size_bytes"])
        return SupportDataItem(
            category: category,
            path: path,
            sizeBytes: sizeBytes,
            matchEvidence: evidence,
            matchConfidence: matchConfidence,
            dataRisk: dataRisk,
            defaultSelected: defaultSelected,
            requiresExplicitApproval: requiresExplicit
        )
    }

    static func parseCategory(_ raw: Any?) -> SupportDataCategory? {
        guard let s = raw as? String, !s.isEmpty else { return nil }
        return SupportDataCategory(rawValue: s)
    }
}
