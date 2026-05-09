import Foundation

import AxionCore

/// Prompt 加载与模板变量注入 (AC1)
struct PromptBuilder {

    // MARK: - Prompt 文件加载

    /// 从指定目录加载 .md 文件，替换 `{{key}}` 模板变量
    static func load(name: String, variables: [String: String], fromDirectory directory: String) throws -> String {
        let path = (directory as NSString).appendingPathComponent("\(name).md")
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return variables.reduce(content) { $0.replacingOccurrences(of: "{{\($1.key)}}", with: $1.value) }
    }

    // MARK: - Prompt 目录查找

    /// 支持 SPM 资源路径和开发路径两种查找策略
    static func resolvePromptDirectory() -> String {
        // Strategy 1: Relative to Package.swift (development)
        let cwd = FileManager.default.currentDirectoryPath
        let cwdPrompts = (cwd as NSString).appendingPathComponent("Prompts")
        if FileManager.default.fileExists(atPath: cwdPrompts) {
            return cwdPrompts
        }

        // Strategy 2: Bundle resource (runtime)
        let bundlePath = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("Prompts").path
        if FileManager.default.fileExists(atPath: bundlePath) {
            return bundlePath
        }

        // Strategy 3: Fallback to CWD Prompts
        return cwdPrompts
    }

    // MARK: - 工具列表格式化

    /// 将工具名列表格式化为 prompt 中可用的工具描述
    static func buildToolListDescription(from tools: [String]) -> String {
        guard !tools.isEmpty else { return "" }
        return tools.joined(separator: ", ")
    }

    // MARK: - 完整 Planner Prompt 组装

    /// 组装完整 planner prompt，包含任务 + 上下文 + 重规划信息
    /// Note: system prompt is loaded separately in LLMPlanner.buildPrompts() — this method only builds the user prompt.
    static func buildPlannerPrompt(
        task: String,
        currentStateSummary: String,
        maxStepsPerPlan: Int,
        replanContext: ReplanContext?
    ) -> String {
        var sections: [String] = [
            "User task:",
            task,
            "",
            "Plan at most \(maxStepsPerPlan) action step(s) in this batch. Prefer fewer.",
        ]

        if !currentStateSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("")
            sections.append("Current screen state:")
            sections.append(currentStateSummary)
        }

        if let replan = replanContext {
            sections.append("")
            sections.append("REPLAN: the previous plan failed at step \(replan.failedStepIndex) (purpose: \"\(replan.failedStep.purpose)\").")
            sections.append("Error: \(replan.errorMessage)")

            if !replan.executedSteps.isEmpty {
                sections.append("")
                sections.append("Already-executed steps (do NOT repeat these — the side effects are already applied):")
                for (i, step) in replan.executedSteps.enumerated() {
                    sections.append("  \(i). \(step.tool) — \(step.purpose)")
                }
            }

            if let history = replan.runHistory, !history.isEmpty {
                sections.append("")
                sections.append("Cumulative run history (do not repeat successful work):")
                for (i, line) in history.suffix(30).enumerated() {
                    sections.append("  \(i). \(line)")
                }
            }

            if let axTree = replan.liveAxTree, !axTree.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("")
                sections.append("Live AX tree/screen state now (already captured; do NOT emit list_windows/get_window_state merely to inspect this same state again):")
                let truncated = String(axTree.prefix(12000))
                sections.append(truncated)
            }

            sections.append("")
            sections.append("Produce a SUFFIX plan that recovers from the failure and completes the remaining work. Skip steps that already executed.")
        } else {
            sections.append("")
            sections.append("Produce the plan.")
        }

        return sections.joined(separator: "\n")
    }
}

