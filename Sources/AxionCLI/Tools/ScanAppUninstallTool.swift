import Foundation
import OpenAgentSDK

import AxionCore

/// `scan_app_uninstall` —— 扫描 App 卸载候选与 support 数据，产出只读 `AppUninstallPlan`
/// （`isReadOnly = true`：只扫描，不执行任何卸载/移动/删除）。需配合 `execute_app_uninstall`
/// （副作用工具）在用户确认后执行。
///
/// 入参：`query`（必填，App 名或 bundle id）、`mode`（可选，默认 `uninstall_with_support_review`）、
/// `search_roots`（可选，默认 `["/Applications", "~/Applications"]`，App 发现根）。
///
/// 安全：多候选/系统保护/越界 → `blocked_reasons`，扫描工具绝不自动执行（AC #2）。低置信度 support
/// 项单列到 `hint_only_support_data_items`（AC #7）。外部提示只读不改风险（AC #11）。
final class ScanAppUninstallTool: ToolProtocol, Sendable {

    let name = "scan_app_uninstall"
    let description = "扫描 App 卸载候选与 ~/Library support 数据，返回只读 AppUninstallPlan（含候选 App、support 数据项、风险分级、阻断原因、外部卸载提示）。本工具只扫描不执行；需用户确认后再用 execute_app_uninstall 执行。安全：多候选/系统保护 App/不在 Applications 目录 → blocked_reasons（不自动执行）；低置信度 support 项单列到 hint_only_support_data_items；高风险或共享目录需 typed/逐项确认。永不永久删除。展示给用户时必须逐项显示完整 support path，不要只在多列表格中截断路径。参数：query(必填，App 显示名或 bundle id)、mode(可选，默认 uninstall_with_support_review：scan_only/uninstall_app_only/uninstall_with_support_review/review_support_data/clean_approved_support_data)、search_roots(可选，App 发现根，默认 [\"/Applications\", \"~/Applications\"])。"
    nonisolated(unsafe) let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "App display name or bundle identifier to find (e.g. 'Slack' or 'com.tinyspeck.slackmacgap').",
            ],
            "mode": [
                "type": "string",
                "enum": [
                    "scan_only", "uninstall_app_only", "uninstall_with_support_review",
                    "review_support_data", "clean_approved_support_data",
                ],
                "description": "Uninstall mode (default uninstall_with_support_review).",
            ],
            "search_roots": [
                "type": "array",
                "items": ["type": "string"],
                "description": "App discovery roots (default [\"/Applications\", \"~/Applications\"]).",
            ],
        ],
        "required": ["query"],
    ]
    let isReadOnly = true

    private let planBuilder: AppUninstallPlanBuilder

    init(planBuilder: AppUninstallPlanBuilder) {
        self.planBuilder = planBuilder
    }

    func call(input: Any, context: ToolContext) async -> ToolResult {
        let toolUseId = context.toolUseId
        guard let params = input as? [String: Any] else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "invalid_input",
                message: "Input must be a JSON object",
                suggestion: "Pass a JSON object with 'query' and optional 'mode'/'search_roots'"
            )
        }

        // query：必填
        if let err = ToolResultHelper.requireStringParam(
            params: params, key: "query", toolUseId: toolUseId,
            error: "missing_query",
            message: "Missing required 'query' parameter",
            suggestion: "Pass an App display name or bundle identifier (e.g. 'Slack' or 'com.example.app')"
        ) { return err }
        let query = (params["query"] as? String) ?? ""

        // mode：可选，默认 uninstall_with_support_review
        let mode: AppUninstallMode
        if let raw = params["mode"] as? String, !raw.isEmpty,
           let parsed = AppUninstallMode(rawValue: raw) {
            mode = parsed
        } else {
            mode = .uninstallWithSupportReview
        }

        // search_roots：可选，默认 ["/Applications", "~/Applications"]（展开 ~）
        let home = NSHomeDirectory()
        let rawRoots = (params["search_roots"] as? [String])?.filter { !$0.isEmpty }
        let rootStrings = rawRoots?.isEmpty == false ? rawRoots! : Self.defaultSearchRoots
        let searchRoots = rootStrings.map { StorageExclusions.standardize($0, home: home) }
            .map { URL(fileURLWithPath: $0) }

        let plan = await planBuilder.build(
            query: query,
            mode: mode,
            homeDirectory: home,
            searchRoots: searchRoots
        )

        return ToolResultHelper.encodeResult(toolUseId: toolUseId, isError: false) { encoder in
            try encoder.encode(plan)
        }
    }

    // MARK: - Helpers

    /// 默认 App 发现根（`~` 相对字符串；调用时按主目录展开）。
    static let defaultSearchRoots: [String] = ["/Applications", "~/Applications"]
}
