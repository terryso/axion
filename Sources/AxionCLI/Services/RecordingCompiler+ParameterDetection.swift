import AxionCore

extension RecordingCompiler {

    // MARK: - Manual Parameter Override

    func applyManualParams(steps: [SkillStep], paramNames: [String])
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

    func replaceArgument(in step: SkillStep, key: String, with newValue: String) -> SkillStep {
        var args = step.arguments
        args[key] = newValue
        return SkillStep(tool: step.tool, arguments: args, waitAfterSeconds: step.waitAfterSeconds)
    }

    // MARK: - Auto Parameter Detection

    func autoDetectParams(steps: [SkillStep], existingParams: Set<String>)
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

    enum ParamPattern {
        case url, filePath, longText
    }

    func detectPattern(_ value: String) -> ParamPattern? {
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

    func paramDescription(for value: String) -> String {
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
