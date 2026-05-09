import Foundation

import AxionCore

/// LLM 输出 -> Plan 解析 (AC4, AC5, AC7)
struct PlanParser {

    // MARK: - 中间解码结构

    /// LLM 原始输出的中间结构（snake_case 字段名）
    private struct RawPlan: Codable {
        let status: String?
        let steps: [RawStep]
        let stopWhen: String
        let message: String?

        enum CodingKeys: String, CodingKey {
            case status, steps, stopWhen, message
        }
    }

    private struct RawStep: Codable {
        let tool: String
        let args: [String: RawValue]?
        let purpose: String?
        let expected_change: String?

        enum CodingKeys: String, CodingKey {
            case tool, args, purpose, expected_change
        }
    }

    /// 灵活解码 JSON 值（String, Int, Double, Bool, Array）
    private enum RawValue: Codable, Equatable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case array([RawValue])

        var toValue: Value {
            switch self {
            case .string(let s): return .string(s)
            case .int(let i): return .int(i)
            case .double(let d): return .int(Int(d))
            case .bool(let b): return .bool(b)
            case .array(let arr):
                return .array(arr.map { $0.toValue })
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .string(s)
            } else if let b = try? container.decode(Bool.self) {
                self = .bool(b)
            } else if let i = try? container.decode(Int.self) {
                self = .int(i)
            } else if let d = try? container.decode(Double.self) {
                self = .double(d)
            } else if let arr = try? container.decode([RawValue].self) {
                self = .array(arr)
            } else {
                self = .string("")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let i): try container.encode(i)
            case .double(let d): try container.encode(d)
            case .bool(let b): try container.encode(b)
            case .array(let arr): try container.encode(arr)
            }
        }
    }

    // MARK: - 公开 API

    /// 从 LLM 原始响应解析 Plan
    static func parse(_ rawResponse: String, task: String, maxSteps: Int) throws -> Plan {
        let jsonString = try stripFences(rawResponse)

        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AxionError.invalidPlan(reason: "Failed to convert response to data. Raw: \(rawResponse.prefix(200))")
        }

        let rawPlan: RawPlan
        do {
            rawPlan = try JSONDecoder().decode(RawPlan.self, from: jsonData)
        } catch {
            throw AxionError.invalidPlan(
                reason: "JSON decode failed: \(error.localizedDescription). Raw response: \(rawResponse.prefix(500))"
            )
        }

        // Handle non-ready statuses
        if let status = rawPlan.status {
            if status == "done" {
                // Task already complete — return a Plan with 0 steps
                return Plan(
                    id: UUID(),
                    task: task,
                    steps: [],
                    stopWhen: [StopCondition(type: .custom, value: rawPlan.stopWhen)],
                    maxRetries: 0
                )
            }
            if status == "blocked" || status == "needs_clarification" {
                let msg = rawPlan.message ?? rawPlan.stopWhen
                throw AxionError.planningFailed(
                    reason: "Planner returned \(status): \(msg)"
                )
            }
        }

        // Validate steps
        guard !rawPlan.steps.isEmpty else {
            throw AxionError.invalidPlan(
                reason: "Plan has no steps (status=\(rawPlan.status ?? "nil")). Raw: \(rawResponse.prefix(300))"
            )
        }

        guard !rawPlan.stopWhen.isEmpty else {
            throw AxionError.invalidPlan(
                reason: "Plan has empty stopWhen. Raw: \(rawResponse.prefix(300))"
            )
        }

        guard rawPlan.steps.count <= maxSteps else {
            throw AxionError.invalidPlan(
                reason: "Plan has \(rawPlan.steps.count) steps, exceeds max \(maxSteps). Raw: \(rawResponse.prefix(300))"
            )
        }

        // Convert RawStep -> Step
        var steps: [Step] = []
        for (i, rawStep) in rawPlan.steps.enumerated() {
            guard !rawStep.tool.isEmpty else {
                throw AxionError.invalidPlan(reason: "Step \(i) missing tool name. Raw: \(rawResponse.prefix(300))")
            }
            let purpose = rawStep.purpose
            guard let purpose, !purpose.isEmpty else {
                throw AxionError.invalidPlan(reason: "Step \(i) missing purpose. Raw: \(rawResponse.prefix(300))")
            }
            let expectedChange = rawStep.expected_change ?? ""

            // Convert args -> parameters
            var parameters: [String: Value] = [:]
            if let args = rawStep.args {
                for (key, rawVal) in args {
                    parameters[key] = rawVal.toValue
                }
            }

            steps.append(Step(
                index: i,
                tool: rawStep.tool,
                parameters: parameters,
                purpose: purpose,
                expectedChange: expectedChange
            ))
        }

        let stopConditions = [StopCondition(type: .custom, value: rawPlan.stopWhen)]

        let plan = Plan(
            id: UUID(),
            task: task,
            steps: steps,
            stopWhen: stopConditions,
            maxRetries: 3
        )

        return try validatePlan(plan, maxSteps: maxSteps)
    }

    /// 剥离 markdown 围栏、前导文本，提取 JSON 对象
    static func stripFences(_ s: String) throws -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try matching ```json...``` or ```...``` fences
        let fencePattern = "^```(?:json)?\\s*([\\s\\S]*?)\\s*```$"
        if let regex = try? NSRegularExpression(pattern: fencePattern, options: .anchorsMatchLines),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           match.numberOfRanges > 1,
           let innerRange = Range(match.range(at: 1), in: trimmed) {
            let inner = String(trimmed[innerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return extractJSONObject(from: inner)
        }

        return extractJSONObject(from: trimmed)
    }

    /// 验证 Plan 结构完整性
    static func validatePlan(_ plan: Plan, maxSteps: Int) throws -> Plan {
        guard !plan.steps.isEmpty else {
            throw AxionError.invalidPlan(reason: "Plan has no steps — at least one step is required")
        }

        guard !plan.stopWhen.isEmpty else {
            throw AxionError.invalidPlan(reason: "Plan has no stopWhen conditions")
        }

        guard plan.steps.count <= maxSteps else {
            throw AxionError.invalidPlan(reason: "Plan has \(plan.steps.count) steps, exceeds max \(maxSteps)")
        }

        for (i, step) in plan.steps.enumerated() {
            guard !step.tool.isEmpty else {
                throw AxionError.invalidPlan(reason: "Step \(i) missing tool name")
            }
            guard !step.purpose.isEmpty else {
                throw AxionError.invalidPlan(reason: "Step \(i) missing purpose")
            }
        }

        return plan
    }

    // MARK: - Private Helpers

    /// Extract a JSON object from text by tracking brace depth and string boundaries
    private static func extractJSONObject(from text: String) -> String {
        let characters = Array(text)
        guard let firstBrace = characters.firstIndex(where: { $0 == "{" }) else {
            return text
        }

        var depth = 0
        var inString = false
        var escaped = false

        for i in firstBrace..<characters.count {
            let char = characters[i]

            if escaped {
                escaped = false
                continue
            }

            if char == "\\" {
                escaped = inString
                continue
            }

            if char == "\"" {
                inString = !inString
                continue
            }

            if inString { continue }

            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    return String(characters[firstBrace...i])
                }
            }
        }

        // If no balanced closing brace, return from first { to end
        return String(characters[firstBrace...])
    }
}
