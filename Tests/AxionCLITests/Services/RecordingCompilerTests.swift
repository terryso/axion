import Testing
import Foundation
@testable import AxionCLI
@testable import AxionCore

@Suite("RecordingCompiler")
struct RecordingCompilerTests {

    private let compiler = RecordingCompiler()

    private func makeRecording(events: [RecordedEvent], name: String = "test") -> Recording {
        Recording(
            name: name,
            createdAt: Date(),
            durationSeconds: 10,
            events: events,
            windowSnapshots: []
        )
    }

    // MARK: - Event Type Mapping (4.3)

    @Test("click event maps to click step")
    func test_clickEvent_mapsToClickStep() throws {
        let events = [
            RecordedEvent(
                type: .click, timestamp: 0.1,
                parameters: ["x": .int(500), "y": .int(300)],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 1)
        let step = result.skill.steps[0]
        #expect(step.tool == "click")
        #expect(step.arguments["x"] == "500")
        #expect(step.arguments["y"] == "300")
    }

    @Test("typeText event maps to type_text step")
    func test_typeTextEvent_mapsToTypeTextStep() {
        let events = [
            RecordedEvent(
                type: .typeText, timestamp: 0.2,
                parameters: ["text": .string("hello")],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 1)
        #expect(result.skill.steps[0].tool == "type_text")
        #expect(result.skill.steps[0].arguments["text"] == "hello")
    }

    @Test("hotkey event maps to hotkey step")
    func test_hotkeyEvent_mapsToHotkeyStep() {
        let events = [
            RecordedEvent(
                type: .hotkey, timestamp: 0.3,
                parameters: ["keys": .string("cmd+c")],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 1)
        #expect(result.skill.steps[0].tool == "hotkey")
        #expect(result.skill.steps[0].arguments["keys"] == "cmd+c")
    }

    @Test("appSwitch event maps to launch_app step")
    func test_appSwitchEvent_mapsToLaunchAppStep() {
        let events = [
            RecordedEvent(
                type: .appSwitch, timestamp: 0.4,
                parameters: ["app_name": .string("Calculator")],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 1)
        #expect(result.skill.steps[0].tool == "launch_app")
        #expect(result.skill.steps[0].arguments["app_name"] == "Calculator")
    }

    @Test("scroll event maps to scroll step")
    func test_scrollEvent_mapsToScrollStep() {
        let events = [
            RecordedEvent(
                type: .scroll, timestamp: 0.5,
                parameters: ["dx": .int(0), "dy": .int(-5)],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 1)
        #expect(result.skill.steps[0].tool == "scroll")
        #expect(result.skill.steps[0].arguments["dx"] == "0")
        #expect(result.skill.steps[0].arguments["dy"] == "-5")
    }

    @Test("double values in parameters are converted to string")
    func test_doubleValues_convertedToString() {
        let events = [
            RecordedEvent(
                type: .scroll, timestamp: 0.5,
                parameters: ["dx": .double(0.0), "dy": .double(-3.5)],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps[0].arguments["dx"] == "0.0")
        #expect(result.skill.steps[0].arguments["dy"] == "-3.5")
    }

    // MARK: - Auto Parameter Detection (4.4)

    @Test("URL pattern detected as parameter")
    func test_autoDetect_urlPattern() {
        let events = [
            RecordedEvent(
                type: .typeText, timestamp: 0.1,
                parameters: ["text": .string("https://example.com/search")],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.parameters.count == 1)
        #expect(result.skill.parameters[0].name == "url")
        #expect(result.skill.steps[0].arguments["text"] == "{{url}}")
    }

    @Test("file path pattern detected as parameter")
    func test_autoDetect_filePathPattern() {
        let events = [
            RecordedEvent(
                type: .typeText, timestamp: 0.1,
                parameters: ["text": .string("/Users/nick/Documents/file.txt")],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.parameters.count == 1)
        #expect(result.skill.parameters[0].name == "file_path")
        #expect(result.skill.steps[0].arguments["text"] == "{{file_path}}")
    }

    @Test("tilde path pattern detected as parameter")
    func test_autoDetect_tildePath() {
        let events = [
            RecordedEvent(
                type: .typeText, timestamp: 0.1,
                parameters: ["text": .string("~/Desktop/test.txt")],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.parameters.count == 1)
        #expect(result.skill.parameters[0].name == "file_path")
    }

    @Test("long text detected as parameter")
    func test_autoDetect_longText() {
        let longText = "this is a really long string that exceeds twenty characters"
        let events = [
            RecordedEvent(
                type: .typeText, timestamp: 0.1,
                parameters: ["text": .string(longText)],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.parameters.count == 1)
        #expect(result.skill.parameters[0].name == "text")
        #expect(result.skill.steps[0].arguments["text"] == "{{text}}")
    }

    @Test("short text is not detected as parameter")
    func test_autoDetect_shortText_notParameter() {
        let events = [
            RecordedEvent(
                type: .typeText, timestamp: 0.1,
                parameters: ["text": .string("hello")],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.parameters.isEmpty)
        #expect(result.skill.steps[0].arguments["text"] == "hello")
    }

    // MARK: - Manual Parameter Override (4.5)

    @Test("manual --param replaces first matching argument")
    func test_manualParam_replacesArgument() {
        let events = [
            RecordedEvent(
                type: .typeText, timestamp: 0.1,
                parameters: ["text": .string("hello world")],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(
            recording: makeRecording(events: events),
            paramNames: ["search_term"]
        )
        #expect(result.skill.steps[0].arguments["text"] == "{{search_term}}")
        let param = result.skill.parameters.first { $0.name == "search_term" }
        #expect(param != nil)
    }

    @Test("multiple manual params replace multiple arguments")
    func test_manualParams_multipleParams() {
        let events = [
            RecordedEvent(
                type: .typeText, timestamp: 0.1,
                parameters: ["text": .string("first value")],
                windowContext: nil
            ),
            RecordedEvent(
                type: .click, timestamp: 0.15,
                parameters: ["x": .int(100), "y": .int(200)],
                windowContext: nil
            ),
            RecordedEvent(
                type: .typeText, timestamp: 0.2,
                parameters: ["text": .string("second value")],
                windowContext: nil
            ),
        ]
        let result = compiler.compile(
            recording: makeRecording(events: events),
            paramNames: ["p1", "p2"]
        )
        #expect(result.skill.parameters.count >= 2)
    }

    // MARK: - Redundancy Optimization (4.6)

    @Test("consecutive identical clicks deduplicated")
    func test_optimize_consecutiveIdenticalClicks() {
        let events = [
            RecordedEvent(type: .click, timestamp: 0.1, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
            RecordedEvent(type: .click, timestamp: 0.2, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
            RecordedEvent(type: .click, timestamp: 0.3, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 1)
        #expect(result.optimizedStepCount == 2)
    }

    @Test("consecutive different clicks are kept")
    func test_optimize_differentClicks_kept() {
        let events = [
            RecordedEvent(type: .click, timestamp: 0.1, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
            RecordedEvent(type: .click, timestamp: 0.2, parameters: ["x": .int(300), "y": .int(400)], windowContext: nil),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 2)
    }

    @Test("consecutive type_text merged into single step")
    func test_optimize_mergeTypeText() {
        let events = [
            RecordedEvent(type: .typeText, timestamp: 0.1, parameters: ["text": .string("hello")], windowContext: nil),
            RecordedEvent(type: .typeText, timestamp: 0.2, parameters: ["text": .string(" world")], windowContext: nil),
            RecordedEvent(type: .typeText, timestamp: 0.3, parameters: ["text": .string("!")], windowContext: nil),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 1)
        #expect(result.skill.steps[0].arguments["text"] == "hello world!")
    }

    @Test("redundant app_switch A→B→A removed")
    func test_optimize_redundantAppSwitch() {
        let events = [
            RecordedEvent(type: .appSwitch, timestamp: 0.1, parameters: ["app_name": .string("Safari")], windowContext: nil),
            RecordedEvent(type: .appSwitch, timestamp: 0.2, parameters: ["app_name": .string("Calculator")], windowContext: nil),
            RecordedEvent(type: .appSwitch, timestamp: 0.3, parameters: ["app_name": .string("Safari")], windowContext: nil),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 1)
        #expect(result.skill.steps[0].arguments["app_name"] == "Safari")
    }

    // MARK: - Error Event (4.7)

    @Test("error events are skipped")
    func test_errorEvents_skipped() {
        let events = [
            RecordedEvent(type: .click, timestamp: 0.1, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
            RecordedEvent(type: .error, timestamp: 0.15, parameters: ["message": .string("oops")], windowContext: nil),
            RecordedEvent(type: .click, timestamp: 0.2, parameters: ["x": .int(300), "y": .int(400)], windowContext: nil),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.count == 2)
        #expect(result.skill.steps[0].tool == "click")
        #expect(result.skill.steps[1].tool == "click")
    }

    @Test("only error events produces empty skill")
    func test_onlyErrorEvents_emptySteps() {
        let events = [
            RecordedEvent(type: .error, timestamp: 0.1, parameters: [:], windowContext: nil),
            RecordedEvent(type: .error, timestamp: 0.2, parameters: [:], windowContext: nil),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.skill.steps.isEmpty)
    }

    // MARK: - Compile Result Properties

    @Test("compile result reports correct detected parameter count")
    func test_compileResult_detectedParamCount() {
        let events = [
            RecordedEvent(type: .typeText, timestamp: 0.1, parameters: ["text": .string("https://example.com")], windowContext: nil),
            RecordedEvent(type: .click, timestamp: 0.2, parameters: ["x": .int(100), "y": .int(200)], windowContext: nil),
            RecordedEvent(type: .typeText, timestamp: 0.3, parameters: ["text": .string("/Users/nick/file.txt")], windowContext: nil),
        ]
        let result = compiler.compile(recording: makeRecording(events: events))
        #expect(result.detectedParameterCount == 2)
    }

    @Test("skill metadata populated from recording")
    func test_skillMetadata_fromRecording() {
        let recording = makeRecording(events: [], name: "my_skill")
        let result = compiler.compile(recording: recording)
        #expect(result.skill.name == "my_skill")
        #expect(result.skill.sourceRecording == "my_skill")
        #expect(result.skill.version == 1)
        #expect(result.skill.description.contains("my_skill"))
    }
}
