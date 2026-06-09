import AxionCore
import Foundation

struct RecordingCompiler {

    /// Result of compiling a recording into a skill.
    struct CompileResult {
        let skill: Skill
        let detectedParameterCount: Int
        let optimizedStepCount: Int
    }

    /// Compile a recording into a reusable skill.
    /// - Parameters:
    ///   - recording: The recording to compile.
    ///   - paramNames: Manually specified parameter names (from `--param`).
    /// - Returns: A `CompileResult` containing the compiled skill and statistics.
    func compile(recording: Recording, paramNames: [String] = []) -> CompileResult {
        var steps = mapEventsToSteps(events: recording.events)
        let preOptimizeCount = steps.count

        steps = optimizeSteps(steps)

        let optimizedStepCount = preOptimizeCount - steps.count

        var allDetectedParams: [(name: String, originalValue: String)] = []

        // Apply manual parameter overrides first
        if !paramNames.isEmpty {
            let manualResult = applyManualParams(steps: steps, paramNames: paramNames)
            steps = manualResult.steps
            allDetectedParams.append(contentsOf: manualResult.detectedParams)
        }

        // Auto-detect parameters in remaining step arguments
        let autoResult = autoDetectParams(steps: steps, existingParams: Set(allDetectedParams.map(\.name)))
        steps = autoResult.steps
        allDetectedParams.append(contentsOf: autoResult.detectedParams)

        let parameters = allDetectedParams.map { name, originalValue in
            SkillParameter(
                name: name,
                description: paramDescription(for: originalValue)
            )
        }

        let skill = Skill(
            name: recording.name,
            description: "操作录制: \(recording.name) (编译自录制文件)",
            createdAt: Date(),
            sourceRecording: recording.name,
            parameters: parameters,
            steps: steps
        )

        return CompileResult(
            skill: skill,
            detectedParameterCount: allDetectedParams.count,
            optimizedStepCount: optimizedStepCount
        )
    }
}
