import Foundation
import OpenAgentSDK

import AxionCore

/// `propose_storage_plan` —— Agent 提交语义分类并物化为「已校验、`approved=false`」的
/// `StoragePlan`（只读工具：只产出计划，不执行任何副作用）。
///
/// Agent 依据 `storage_scan` 返回的底层信号 + 目录上下文 + 用户意图，生成动态分类后，
/// 必须通过本工具提交（而非自由文本），保证源路径经 `StoragePlanBuilder` 安全校验。
/// 每项 schema：`{source, suggested_category, suggested_action, target?, reason, confidence}`。
final class ProposeStoragePlanTool: ToolProtocol, Sendable {

    let name = "propose_storage_plan"
    let description = "提交对扫描文件的语义分类整理计划，返回经安全校验的 StoragePlan（所有项 approved=false，需用户确认后才执行）。安全红线：source 必须在扫描根之下、未被排除、实际存在、非 symlink 目标；默认动作 scan_only；永不 delete；违规项会被丢弃并在 excluded_notes 中说明。本工具只产出计划，不移动/删除任何文件。参数：proposals(对象数组：source/suggested_category/suggested_action/ target?/reason/confidence)、surface(run 或 chat，默认 run)、scan_roots(与 storage_scan 一致的根路径数组，用于校验)。"
    nonisolated(unsafe) let inputSchema: ToolInputSchema = [
        "type": "object",
        "properties": [
            "proposals": [
                "type": "array",
                "description": "Classification proposals",
                "items": [
                    "type": "object",
                    "properties": [
                        "source": ["type": "string", "description": "Absolute source path (must be within scan_roots)"],
                        "suggested_category": ["type": "string", "description": "Dynamic category label (e.g. invoices, installers-to-clean)"],
                        "suggested_action": [
                            "type": "string",
                            "enum": ["scan_only", "move", "trash", "create_directory", "uninstall_app"],
                            "description": "Suggested action (default scan_only)",
                        ],
                        "target": ["type": "string", "description": "Suggested target path (optional)"],
                        "reason": ["type": "string", "description": "Why this classification/action"],
                        "confidence": [
                            "type": "string",
                            "enum": ["high", "medium", "low"],
                            "description": "Confidence in the classification",
                        ],
                    ],
                    "required": ["source", "suggested_action", "reason"],
                ],
            ],
            "surface": [
                "type": "string",
                "enum": ["run", "chat"],
                "description": "Entry surface (default run)",
            ],
            "scan_roots": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Scan roots used for source validation (same as storage_scan roots)",
            ],
        ],
        "required": ["proposals", "scan_roots"],
    ]
    let isReadOnly = true

    private let config: StorageConfig
    private let builder: StoragePlanBuilder

    init(config: StorageConfig = .default, builder: StoragePlanBuilder = StoragePlanBuilder()) {
        self.config = config
        self.builder = builder
    }

    func call(input: Any, context: ToolContext) async -> ToolResult {
        let toolUseId = context.toolUseId
        guard let params = input as? [String: Any] else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "invalid_input",
                message: "Input must be a JSON object",
                suggestion: "Pass a JSON object with 'proposals', 'scan_roots', and optional 'surface'"
            )
        }

        // scan_roots：必填（用于校验 source 在扫描范围内）
        guard let rawRoots = params["scan_roots"] as? [String], !rawRoots.isEmpty else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "missing_scan_roots",
                message: "Missing required 'scan_roots' parameter",
                suggestion: "Provide 'scan_roots' as the same root paths passed to storage_scan"
            )
        }
        let scanRoots = rawRoots.map { URL(fileURLWithPath: $0) }

        // surface
        let surface: StorageSurface
        switch (params["surface"] as? String) ?? "run" {
        case "chat": surface = .chat
        default: surface = .run
        }

        // proposals：必填
        guard let rawProposals = params["proposals"] as? [[String: Any]], !rawProposals.isEmpty else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "missing_proposals",
                message: "Missing or empty 'proposals' parameter",
                suggestion: "Provide at least one proposal object {source, suggested_action, reason}"
            )
        }

        let proposals = rawProposals.compactMap { Self.parseProposal($0) }
        guard !proposals.isEmpty else {
            return ToolResultHelper.errorResult(
                toolUseId: toolUseId,
                error: "no_valid_proposals",
                message: "No proposals with a non-empty 'source' could be parsed",
                suggestion: "Ensure every proposal includes a non-empty 'source' absolute path"
            )
        }

        // 排除规则：内置集 + 用户配置；includeHidden=true（计划校验不因隐藏属性单独拒绝，
        // 仍受 scanRoots/exists/system/git/devcache/symlink 等硬约束保护）。
        let exclusions = StorageExclusions(
            excludedRoots: config.excludedPaths,
            includeHidden: true,
            homeDirectory: NSHomeDirectory()
        )

        let plan = await builder.buildPlan(
            proposals: proposals,
            scanRoots: scanRoots,
            exclusions: exclusions,
            surface: surface
        )

        return ToolResultHelper.encodeResult(toolUseId: toolUseId, isError: false) { encoder in
            try encoder.encode(plan)
        }
    }

    // MARK: - Parsing

    static func parseProposal(_ raw: [String: Any]) -> ProposedItem? {
        guard let source = raw["source"] as? String, !source.isEmpty else { return nil }
        let action = parseAction(raw["suggested_action"]) ?? .scanOnly
        let target = (raw["target"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let reason = (raw["reason"] as? String) ?? ""
        let confidence = (raw["confidence"] as? String).flatMap { StorageConfidence(rawValue: $0.lowercased()) } ?? .medium
        let category = (raw["suggested_category"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return ProposedItem(
            source: source,
            suggestedCategory: category,
            suggestedAction: action,
            target: target,
            reason: reason,
            confidence: confidence
        )
    }

    static func parseAction(_ raw: Any?) -> StorageAction? {
        guard let s = raw as? String else { return nil }
        return StorageAction(rawValue: s)
    }
}
