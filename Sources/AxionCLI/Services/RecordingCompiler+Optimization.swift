import AxionCore

extension RecordingCompiler {

    // MARK: - Optimization

    func optimizeSteps(_ steps: [SkillStep]) -> [SkillStep] {
        var result = steps

        // 1. Merge consecutive type_text steps
        result = mergeConsecutiveTypeText(result)

        // 2. Remove redundant app_switch (A→B→A pattern)
        result = removeRedundantAppSwitch(result)

        // 3. Deduplicate consecutive identical clicks
        result = deduplicateConsecutiveClicks(result)

        return result
    }

    func mergeConsecutiveTypeText(_ steps: [SkillStep]) -> [SkillStep] {
        guard !steps.isEmpty else { return [] }

        var result: [SkillStep] = [steps[0]]

        for i in 1..<steps.count {
            let current = steps[i]
            let lastIndex = result.count - 1

            if current.tool == "type_text" && result[lastIndex].tool == "type_text" {
                let existingText = result[lastIndex].arguments["text"] ?? ""
                let newText = current.arguments["text"] ?? ""
                let mergedText = existingText + newText
                result[lastIndex] = SkillStep(
                    tool: "type_text",
                    arguments: ["text": mergedText],
                    waitAfterSeconds: current.waitAfterSeconds
                )
            } else {
                result.append(current)
            }
        }

        return result
    }

    func removeRedundantAppSwitch(_ steps: [SkillStep]) -> [SkillStep] {
        guard steps.count >= 3 else { return steps }

        var result: [SkillStep] = []

        var i = 0
        while i < steps.count {
            // Check for A→B→A pattern where A and B are both launch_app
            if i + 2 < steps.count
                && steps[i].tool == "launch_app"
                && steps[i + 1].tool == "launch_app"
                && steps[i + 2].tool == "launch_app"
                && steps[i].arguments["app_name"] != nil
                && steps[i].arguments["app_name"] == steps[i + 2].arguments["app_name"]
            {
                // Skip the middle switch (i+1) and the return switch (i+2)
                result.append(steps[i])
                i += 3
            } else {
                result.append(steps[i])
                i += 1
            }
        }

        return result
    }

    func deduplicateConsecutiveClicks(_ steps: [SkillStep]) -> [SkillStep] {
        guard !steps.isEmpty else { return [] }

        var result: [SkillStep] = [steps[0]]

        for i in 1..<steps.count {
            let current = steps[i]
            let lastIndex = result.count - 1

            if current.tool == "click"
                && result[lastIndex].tool == "click"
                && current.arguments == result[lastIndex].arguments
            {
                // Replace with the later click (keep the last one)
                result[lastIndex] = current
            } else {
                result.append(current)
            }
        }

        return result
    }
}
