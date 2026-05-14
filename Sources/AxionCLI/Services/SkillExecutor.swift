import AxionCore
import Foundation

struct SkillExecutionResult: Sendable {
    let success: Bool
    let stepsExecuted: Int
    let failedStepIndex: Int?
    let durationSeconds: TimeInterval
    let errorMessage: String?
}

struct SkillExecutor {

    private let client: MCPClientProtocol

    init(client: MCPClientProtocol) {
        self.client = client
    }

    func execute(skill: Skill, paramValues: [String: String]) async throws -> SkillExecutionResult {
        let startTime = Date()

        for (index, step) in skill.steps.enumerated() {
            let resolvedArgs = try resolveParams(
                step.arguments,
                paramValues: paramValues,
                parameters: skill.parameters
            )
            let mcpArgs = toStringValueDict(resolvedArgs)

            do {
                _ = try await client.callTool(name: step.tool, arguments: mcpArgs)
            } catch {
                // Retry once
                do {
                    _ = try await client.callTool(name: step.tool, arguments: mcpArgs)
                } catch let retryError {
                    let elapsed = Date().timeIntervalSince(startTime)
                    return SkillExecutionResult(
                        success: false,
                        stepsExecuted: index,
                        failedStepIndex: index,
                        durationSeconds: elapsed,
                        errorMessage: "步骤 \(index + 1) 失败: \(retryError.localizedDescription)"
                    )
                }
            }

            if step.waitAfterSeconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(step.waitAfterSeconds * 1_000_000_000))
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        return SkillExecutionResult(
            success: true,
            stepsExecuted: skill.steps.count,
            failedStepIndex: nil,
            durationSeconds: elapsed,
            errorMessage: nil
        )
    }

    // MARK: - Parameter Resolution

    func resolveParams(
        _ arguments: [String: String],
        paramValues: [String: String],
        parameters: [SkillParameter]
    ) throws -> [String: String] {
        let paramDefaults = Dictionary(uniqueKeysWithValues: parameters.compactMap { p in
            p.defaultValue.map { (p.name, $0) }
        })

        var resolved: [String: String] = [:]
        for (key, value) in arguments {
            resolved[key] = try resolveTemplate(
                value,
                paramValues: paramValues,
                paramDefaults: paramDefaults,
                requiredParams: Set(parameters.filter { $0.defaultValue == nil }.map(\.name))
            )
        }
        return resolved
    }

    private func resolveTemplate(
        _ value: String,
        paramValues: [String: String],
        paramDefaults: [String: String],
        requiredParams: Set<String>
    ) throws -> String {
        guard value.contains("{{") else { return value }

        var result = value
        // Match {{param_name}} patterns
        let pattern = "\\{\\{(\\w+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }

        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        // Process in reverse to maintain indices
        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: value) else { continue }
            let paramName = String(value[range])

            if let provided = paramValues[paramName] {
                result = result.replacingOccurrences(of: "{{\(paramName)}}", with: provided)
            } else if let defaultVal = paramDefaults[paramName] {
                result = result.replacingOccurrences(of: "{{\(paramName)}}", with: defaultVal)
            } else if requiredParams.contains(paramName) {
                throw AxionError.configError(reason: "缺少必需参数: \(paramName)")
            }
        }
        return result
    }

    // MARK: - Type Conversion

    func toStringValueDict(_ arguments: [String: String]) -> [String: AxionCore.Value] {
        arguments.mapValues { stringValueToValue($0) }
    }

    func stringValueToValue(_ s: String) -> AxionCore.Value {
        if let i = Int(s) {
            return .int(i)
        }
        return .string(s)
    }
}
