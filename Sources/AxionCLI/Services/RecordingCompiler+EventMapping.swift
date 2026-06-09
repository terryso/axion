import AxionCore

extension RecordingCompiler {

    // MARK: - Event Mapping

    func mapEventsToSteps(events: [RecordedEvent]) -> [SkillStep] {
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

    func mapClick(_ event: RecordedEvent) -> SkillStep {
        SkillStep(
            tool: "click",
            arguments: [
                "x": stringValue(event.parameters["x"]),
                "y": stringValue(event.parameters["y"]),
            ]
        )
    }

    func mapTypeText(_ event: RecordedEvent) -> SkillStep {
        SkillStep(
            tool: "type_text",
            arguments: ["text": stringValue(event.parameters["text"])]
        )
    }

    func mapHotkey(_ event: RecordedEvent) -> SkillStep {
        SkillStep(
            tool: "hotkey",
            arguments: ["keys": stringValue(event.parameters["keys"])]
        )
    }

    func mapAppSwitch(_ event: RecordedEvent) -> SkillStep {
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

    func mapScroll(_ event: RecordedEvent) -> SkillStep {
        SkillStep(
            tool: "scroll",
            arguments: [
                "dx": stringValue(event.parameters["dx"]),
                "dy": stringValue(event.parameters["dy"]),
            ]
        )
    }

    // MARK: - JSONValue Extraction

    func stringValue(_ value: JSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return ""
        }
    }
}
