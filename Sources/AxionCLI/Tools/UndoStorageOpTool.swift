import Foundation
import OpenAgentSDK

import AxionCore

/// `undo_storage_op` —— 按 manifest 逆向恢复上一次整理（有副作用，`isReadOnly = false`）。
///
/// 恢复语义：`move` 移回原位、`trash` 从废纸篓移回、空目录移除；无法恢复项给出原因
/// （`source_already_exists` / `target_missing` / `item_no_longer_in_trash` /
/// `directory_not_empty`）。省略 `operation_id` 时撤销最近一次可撤销操作。撤销结果写回
/// manifest（`undoneAt` + 逐项 `undoResults`），可审计。
final class UndoStorageOpTool: ToolProtocol, Sendable {

    let name = "undo_storage_op"
    let description = "按 manifest 逆向恢复上一次文件整理：move 移回原位、trash 从系统废纸篓移回、create_directory 仅在目录为空时移除。无法恢复的项会给出明确原因（source_already_exists/target_missing/item_no_longer_in_trash/directory_not_empty），不影响其余可恢复项。省略 operation_id 时撤销最近一次可撤销操作。返回更新后的 manifest（含 undone_at 与逐项 undo_results）。"
    nonisolated(unsafe) let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": [
            "operation_id": [
                "type": "string",
                "description": "Optional operation ID to undo. Omit to undo the most recent undoable operation.",
            ],
            "surface": [
                "type": "string",
                "enum": ["run", "chat"],
                "description": "Entry surface (default run).",
            ],
        ],
        "required": [],
    ]
    let isReadOnly = false

    private let undoer: StorageUndoing
    private let config: StorageConfig

    init(undoer: StorageUndoing, config: StorageConfig = .default) {
        self.undoer = undoer
        self.config = config
    }

    func call(input: Any, context: ToolContext) async -> ToolResult {
        let toolUseId = context.toolUseId
        let params = (input as? [String: Any]) ?? [:]

        let operationId = (params["operation_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let _ = (params["surface"] as? String) ?? "run"  // surface 保留供未来入口语义（39.4）

        // Pass the configured storageOpsDir (mirrors ExecuteStoragePlanTool) so the request
        // carries the real ops dir rather than a hardcoded default. The injected manifestStore
        // (created in AgentBuilder from the same config) is what the service actually reads/writes;
        // this keeps the two tools symmetric and future-proofs the request field.
        let request = UndoRequest(
            operationId: operationId,
            storageOpsDir: config.storageOpsDir,
            homeDirectory: NSHomeDirectory()
        )

        guard let result = await undoer.undo(request) else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "no_undoable_manifest",
                message: "No undoable storage manifest found",
                suggestion: "Execute a storage plan first (execute_storage_plan), or pass a valid operation_id"
            )
        }

        return ToolResultHelper.encodeResult(toolUseId: toolUseId, isError: false) { encoder in
            try encoder.encode(result.manifest)
        }
    }
}
