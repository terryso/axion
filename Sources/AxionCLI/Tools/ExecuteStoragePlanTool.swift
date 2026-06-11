import Foundation
import OpenAgentSDK

import AxionCore

/// `execute_storage_plan` —— 执行用户**已确认**的整理项（首个有副作用的 storage 工具，
/// `isReadOnly = false`）。
///
/// 安全红线：只接受 `move` / `trash` / `create_directory` / `scan_only`；**永不 delete**
/// （不存在 `delete` 动作）；`uninstall_app` 属另一工具（Story 39.3），收到即拒绝并记入
/// manifest `errors`。`trash` 走系统废纸篓（可恢复）。执行前先写 manifest 草稿
/// （`status = planned`），可经 `undo_storage_op` 撤销。
///
/// 入参即「已批准的执行集」——审批决策由调用方 / 入口在调用工具**之前**完成（`run` 走终端
/// 确认，交互模式走逐项确认；39.4 再统一 `approvePlan` / `approveItem` 结构化语义）。
/// executor 执行前对每项 source **独立重校验**（scan_roots / exclusions / 存在 / 非 symlink /
/// action 白名单），违规项丢弃 + 记 `errors`，不执行。
final class ExecuteStoragePlanTool: ToolProtocol, Sendable {

    let name = "execute_storage_plan"
    let description = "执行用户已确认的文件整理项（移动 / 移入废纸篓 / 创建目录），返回可审计的 StorageManifest（含逐项结果与摘要）。安全红线：只接受 move/trash/create_directory/scan_only；永不永久删除（不存在 delete 动作）；trash 走系统废纸篓（可恢复）；uninstall_app 属另一工具（39.3），收到即拒绝并记入 errors。执行前先写 manifest 草稿，可经 undo_storage_op 撤销。executor 会独立重校验每项 source（必须在 scan_roots 之下、未被排除、实际存在、非 symlink 目标），违规项丢弃不执行。参数：operation_id(必填，来自 propose_storage_plan)、scan_roots(必填，用于重校验 source 范围)、items(必填，对象数组：action/source/target?/size_bytes?/reason?/evidence?)、surface(run 或 chat，默认 run)、user_request(可选，原任务)。"
    nonisolated(unsafe) let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": [
            "operation_id": [
                "type": "string",
                "description": "Operation ID passed through from propose_storage_plan (links execution to plan for audit).",
            ],
            "scan_roots": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Scan roots used to re-validate that every source is within an approved scope.",
            ],
            "items": [
                "type": "array",
                "description": "Approved items to execute.",
                "items": [
                    "type": "object",
                    "properties": [
                        "action": [
                            "type": "string",
                            "enum": ["scan_only", "move", "trash", "create_directory"],
                            "description": "Action to execute (uninstall_app/delete are rejected).",
                        ],
                        "source": ["type": "string", "description": "Absolute source path (for create_directory, the directory to create)."],
                        "target": ["type": "string", "description": "Destination path (move only)."],
                        "size_bytes": ["type": "integer", "description": "Optional size hint (executor re-reads from disk)."],
                        "reason": ["type": "string", "description": "Why this action."],
                        "evidence": [
                            "type": "object",
                            "properties": [
                                "rule": ["type": "string"],
                                "source": ["type": "string"],
                                "confidence": ["type": "string", "enum": ["high", "medium", "low"]],
                            ],
                        ],
                    ],
                    "required": ["action", "source"],
                ],
            ],
            "surface": [
                "type": "string",
                "enum": ["run", "chat"],
                "description": "Entry surface (default run).",
            ],
            "user_request": [
                "type": "string",
                "description": "Original user task (recorded in manifest for audit).",
            ],
        ],
        "required": ["operation_id", "scan_roots", "items"],
    ]
    let isReadOnly = false

    private let executor: StorageExecuting
    private let config: StorageConfig

    init(executor: StorageExecuting, config: StorageConfig = .default) {
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
                suggestion: "Pass a JSON object with 'operation_id', 'scan_roots', 'items', and optional 'surface'/'user_request'"
            )
        }

        // operation_id：必填
        if let err = ToolResultHelper.requireStringParam(
            params: params, key: "operation_id", toolUseId: toolUseId,
            error: "missing_operation_id",
            message: "Missing required 'operation_id' parameter",
            suggestion: "Pass the operation_id returned by propose_storage_plan"
        ) { return err }

        // scan_roots：必填且非空
        guard let rawRoots = params["scan_roots"] as? [String], !rawRoots.isEmpty else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "missing_scan_roots",
                message: "Missing or empty 'scan_roots' parameter",
                suggestion: "Provide 'scan_roots' as the same root paths passed to storage_scan / propose_storage_plan"
            )
        }

        // items：必填且非空
        guard let rawItems = params["items"] as? [[String: Any]], !rawItems.isEmpty else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "missing_items",
                message: "Missing or empty 'items' parameter",
                suggestion: "Provide at least one approved item {action, source, target?}"
            )
        }

        // 解析项；无法识别的 action（如 delete / 缺 source）在解析阶段丢弃（安全：永不执行）。
        // uninstallApp 解析为合法 StorageAction 透传给 executor，由其白名单拒绝 + 记 errors（审计）。
        let items = rawItems.compactMap { Self.parseItem($0) }
        guard !items.isEmpty else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "no_valid_items",
                message: "No items with a non-empty 'source' and recognized 'action' could be parsed",
                suggestion: "Ensure every item includes a non-empty 'source' and an action of scan_only/move/trash/create_directory"
            )
        }

        // surface
        let surface: StorageSurface
        switch (params["surface"] as? String) ?? "run" {
        case "chat": surface = .chat
        default: surface = .run
        }

        let operationId = params["operation_id"] as? String ?? ""
        let userRequest = (params["user_request"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let request = ExecuteRequest(
            operationId: operationId,
            surface: surface,
            scanRoots: rawRoots.map { URL(fileURLWithPath: $0) },
            userRequest: userRequest,
            items: items,
            homeDirectory: NSHomeDirectory(),
            storageOpsDir: config.storageOpsDir
        )

        let result = await executor.execute(request)

        return ToolResultHelper.encodeResult(toolUseId: toolUseId, isError: false) { encoder in
            try encoder.encode(result.manifest)
        }
    }

    // MARK: - Parsing

    static func parseItem(_ raw: [String: Any]) -> ExecutionItem? {
        guard let source = raw["source"] as? String, !source.isEmpty else { return nil }
        // action：必须是合法 StorageAction（含 uninstallApp —— 透传给 executor 审计拒绝）。
        // 无法识别的 action（如 delete）返回 nil，解析阶段即丢弃，永不执行。
        guard let action = parseAction(raw["action"]) else { return nil }
        let target = (raw["target"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let reason = (raw["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let evidence = parseEvidence(raw["evidence"])
        let sizeBytes = parseSizeBytes(raw["size_bytes"])
        return ExecutionItem(
            action: action,
            source: source,
            target: target,
            reason: reason,
            evidence: evidence,
            sizeBytes: sizeBytes
        )
    }

    static func parseAction(_ raw: Any?) -> StorageAction? {
        guard let s = raw as? String, !s.isEmpty else { return nil }
        return StorageAction(rawValue: s)
    }

    static func parseEvidence(_ raw: Any?) -> StorageEvidence? {
        guard let dict = raw as? [String: Any] else { return nil }
        let rule = (dict["rule"] as? String) ?? ""
        let source = (dict["source"] as? String) ?? ""
        let confidence = (dict["confidence"] as? String)
            .flatMap { StorageConfidence(rawValue: $0.lowercased()) } ?? .medium
        return StorageEvidence(rule: rule, source: source, confidence: confidence)
    }

    static func parseSizeBytes(_ raw: Any?) -> Int64 {
        if let v = raw as? Int { return Int64(v) }
        if let v = raw as? Double { return Int64(v) }
        return 0
    }
}
