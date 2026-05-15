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

    // MARK: - Event Mapping

    private func mapEventsToSteps(events: [RecordedEvent]) -> [SkillStep] {
        events.compactMap { event -> SkillStep? in
            switch event.type {
            case .click:
                return mapClick(event)
            case .typeText:
                return mapTypeText(event)
            case .hotkey:
                return mapHotkey(event)
            case .appSwitch:
                return mapAppSwitch(event)
            case .scroll:
                return mapScroll(event)
            case .error:
                return nil
            }
        }
    }

    private func mapClick(_ event: RecordedEvent) -> SkillStep {
        SkillStep(
            tool: "click",
            arguments: [
                "x": stringValue(event.parameters["x"]),
                "y": stringValue(event.parameters["y"]),
            ]
        )
    }

    private func mapTypeText(_ event: RecordedEvent) -> SkillStep {
        SkillStep(
            tool: "type_text",
            arguments: ["text": stringValue(event.parameters["text"])]
        )
    }

    private func mapHotkey(_ event: RecordedEvent) -> SkillStep {
        SkillStep(
            tool: "hotkey",
            arguments: ["keys": stringValue(event.parameters["keys"])]
        )
    }

    private func mapAppSwitch(_ event: RecordedEvent) -> SkillStep {
        // Prefer bundle_id for reliable app resolution across locales
        let appName: String
        if let bundleId = event.parameters["bundle_id"], !stringValue(bundleId).isEmpty {
            appName = stringValue(bundleId)
        } else {
            appName = stringValue(event.parameters["app_name"])
        }
        return SkillStep(
            tool: "launch_app",
            arguments: ["app_name": appName]
        )
    }

    private func mapScroll(_ event: RecordedEvent) -> SkillStep {
        SkillStep(
            tool: "scroll",
            arguments: [
                "dx": stringValue(event.parameters["dx"]),
                "dy": stringValue(event.parameters["dy"]),
            ]
        )
    }

    // MARK: - JSONValue Extraction

    private func stringValue(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return ""
        }
    }

    // MARK: - Optimization

    private func optimizeSteps(_ steps: [SkillStep]) -> [SkillStep] {
        var result = steps

        // 1. Merge consecutive type_text steps
        result = mergeConsecutiveTypeText(result)

        // 2. Remove redundant app_switch (A→B→A pattern)
        result = removeRedundantAppSwitch(result)

        // 3. Deduplicate consecutive identical clicks
        result = deduplicateConsecutiveClicks(result)

        return result
    }

    private func mergeConsecutiveTypeText(_ steps: [SkillStep]) -> [SkillStep] {
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

    private func removeRedundantAppSwitch(_ steps: [SkillStep]) -> [SkillStep] {
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

    private func deduplicateConsecutiveClicks(_ steps: [SkillStep]) -> [SkillStep] {
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

    // MARK: - Manual Parameter Override

    private func applyManualParams(steps: [SkillStep], paramNames: [String])
        -> (steps: [SkillStep], detectedParams: [(name: String, originalValue: String)])
    {
        var detectedParams: [(name: String, originalValue: String)] = []
        var result = steps

        for paramName in paramNames {
            var found = false
            for i in 0..<result.count {
                for (key, value) in result[i].arguments {
                    if !value.isEmpty && !value.hasPrefix("{{") {
                        result[i] = replaceArgument(in: result[i], key: key, with: "{{\(paramName)}}")
                        detectedParams.append((name: paramName, originalValue: value))
                        found = true
                        break
                    }
                }
                if found { break }
            }
        }

        return (result, detectedParams)
    }

    private func replaceArgument(in step: SkillStep, key: String, with newValue: String) -> SkillStep {
        var args = step.arguments
        args[key] = newValue
        return SkillStep(tool: step.tool, arguments: args, waitAfterSeconds: step.waitAfterSeconds)
    }

    // MARK: - Auto Parameter Detection

    private func autoDetectParams(steps: [SkillStep], existingParams: Set<String>)
        -> (steps: [SkillStep], detectedParams: [(name: String, originalValue: String)])
    {
        var detectedParams: [(name: String, originalValue: String)] = []
        var result = steps
        var usedNames = existingParams
        var urlCounter = 0
        var filePathCounter = 0
        var textCounter = 0

        for i in 0..<result.count {
            for key in result[i].arguments.keys.sorted() {
                let value = result[i].arguments[key]!
                guard !value.hasPrefix("{{") else { continue }

                let pattern = detectPattern(value)
                if let pattern {
                    let paramName: String
                    switch pattern {
                    case .url:
                        paramName = urlCounter == 0 ? "url" : "url_\(urlCounter + 1)"
                        urlCounter += 1
                    case .filePath:
                        paramName = filePathCounter == 0 ? "file_path" : "file_path_\(filePathCounter + 1)"
                        filePathCounter += 1
                    case .longText:
                        paramName = textCounter == 0 ? "text" : "text_\(textCounter + 1)"
                        textCounter += 1
                    }

                    let uniqueName: String
                    if !usedNames.contains(paramName) {
                        uniqueName = paramName
                    } else {
                        var suffix = 2
                        while usedNames.contains("\(paramName)_\(suffix)") {
                            suffix += 1
                        }
                        uniqueName = "\(paramName)_\(suffix)"
                    }
                    usedNames.insert(uniqueName)
                    detectedParams.append((name: uniqueName, originalValue: value))
                    result[i] = replaceArgument(in: result[i], key: key, with: "{{\(uniqueName)}}")
                }
            }
        }

        return (result, detectedParams)
    }

    private enum ParamPattern {
        case url, filePath, longText
    }

    private func detectPattern(_ value: String) -> ParamPattern? {
        if value.range(of: #"^https?://.*"#, options: .regularExpression) != nil {
            return .url
        }
        if value.range(of: #"^~/.*"#, options: .regularExpression) != nil
            || value.range(of: #"^/Users/.*"#, options: .regularExpression) != nil
        {
            return .filePath
        }
        if value.count > 20 {
            return .longText
        }
        return nil
    }

    private func paramDescription(for value: String) -> String {
        if value.range(of: #"^https?://.*"#, options: .regularExpression) != nil {
            return "自动检测: URL 模式"
        }
        if value.range(of: #"^~/.*"#, options: .regularExpression) != nil
            || value.range(of: #"^/Users/.*"#, options: .regularExpression) != nil
        {
            return "自动检测: 文件路径模式"
        }
        if value.count > 20 {
            return "自动检测: 长文本"
        }
        return "手动指定参数"
    }
}
