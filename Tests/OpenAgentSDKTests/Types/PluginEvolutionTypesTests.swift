import XCTest
@testable import OpenAgentSDK

final class PluginEvolutionTypesTests: XCTestCase {

    // MARK: - EvolutionPluginConfig

    func testEvolutionPluginConfigDefaults() {
        let config = EvolutionPluginConfig(name: "test-plugin")
        XCTAssertEqual(config.name, "test-plugin")
        XCTAssertTrue(config.enabled)
        XCTAssertNil(config.config)
    }

    func testEvolutionPluginConfigCustom() {
        let config = EvolutionPluginConfig(
            name: "my-plugin",
            enabled: false,
            config: ["key": "value"]
        )
        XCTAssertEqual(config.name, "my-plugin")
        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.config, ["key": "value"])
    }

    func testEvolutionPluginConfigTrimsName() {
        let config = EvolutionPluginConfig(name: "  spaced  ")
        XCTAssertEqual(config.name, "spaced")
    }

    // Note: precondition validation for empty/whitespace-only name is
    // enforced at runtime via precondition() and cannot be tested
    // in-process since it traps. The guard exists in the init and fires
    // at runtime. Verified manually that EvolutionPluginConfig(name: "")
    // and EvolutionPluginConfig(name: "   ") both trigger preconditionFailure.

    func testEvolutionPluginConfigCodableRoundTrip() throws {
        let config = EvolutionPluginConfig(
            name: "codable-plugin",
            enabled: false,
            config: ["k1": "v1", "k2": "v2"]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EvolutionPluginConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testEvolutionPluginConfigEquatable() {
        let a = EvolutionPluginConfig(name: "a", enabled: true, config: nil)
        let b = EvolutionPluginConfig(name: "a", enabled: true, config: nil)
        let c = EvolutionPluginConfig(name: "a", enabled: false, config: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - PluginLifecyclePhase

    func testPluginLifecyclePhaseCases() {
        let allCases = PluginLifecyclePhase.allCases
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.initialize))
        XCTAssertTrue(allCases.contains(.prefetch))
        XCTAssertTrue(allCases.contains(.syncTurn))
        XCTAssertTrue(allCases.contains(.sessionEnd))
        XCTAssertTrue(allCases.contains(.preCompress))
    }

    func testPluginLifecyclePhaseRawValues() {
        XCTAssertEqual(PluginLifecyclePhase.initialize.rawValue, "initialize")
        XCTAssertEqual(PluginLifecyclePhase.prefetch.rawValue, "prefetch")
        XCTAssertEqual(PluginLifecyclePhase.syncTurn.rawValue, "syncTurn")
        XCTAssertEqual(PluginLifecyclePhase.sessionEnd.rawValue, "sessionEnd")
        XCTAssertEqual(PluginLifecyclePhase.preCompress.rawValue, "preCompress")
    }

    func testPluginLifecyclePhaseRawValueRoundTrip() {
        for phase in PluginLifecyclePhase.allCases {
            XCTAssertEqual(PluginLifecyclePhase(rawValue: phase.rawValue), phase)
        }
    }

    func testPluginLifecyclePhaseCodableRoundTrip() throws {
        for phase in PluginLifecyclePhase.allCases {
            let encoder = JSONEncoder()
            let data = try encoder.encode(phase)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(PluginLifecyclePhase.self, from: data)
            XCTAssertEqual(decoded, phase, "Codable round-trip failed for \(phase)")
        }
    }

    // MARK: - PluginContext

    func testPluginContextConstruction() {
        let context = PluginContext(
            sessionId: "sess-1",
            messages: [],
            currentQuery: "hello",
            model: "claude-sonnet-4-6",
            provider: .anthropic
        )
        XCTAssertEqual(context.sessionId, "sess-1")
        XCTAssertTrue(context.messages.isEmpty)
        XCTAssertEqual(context.currentQuery, "hello")
        XCTAssertEqual(context.model, "claude-sonnet-4-6")
        XCTAssertEqual(context.provider, .anthropic)
    }

    func testPluginContextEquality() {
        let a = PluginContext(
            sessionId: "s",
            messages: [],
            currentQuery: nil,
            model: "m",
            provider: .anthropic
        )
        let b = PluginContext(
            sessionId: "s",
            messages: [],
            currentQuery: nil,
            model: "m",
            provider: .anthropic
        )
        XCTAssertEqual(a, b)
    }

    func testPluginContextInequalityBySessionId() {
        let a = PluginContext(sessionId: "s1", messages: [], model: "m", provider: .anthropic)
        let b = PluginContext(sessionId: "s2", messages: [], model: "m", provider: .anthropic)
        XCTAssertNotEqual(a, b)
    }

    func testPluginContextInequalityByModel() {
        let a = PluginContext(sessionId: "s", messages: [], model: "m1", provider: .anthropic)
        let b = PluginContext(sessionId: "s", messages: [], model: "m2", provider: .anthropic)
        XCTAssertNotEqual(a, b)
    }

    func testPluginContextInequalityByProvider() {
        let a = PluginContext(sessionId: "s", messages: [], model: "m", provider: .anthropic)
        let b = PluginContext(sessionId: "s", messages: [], model: "m", provider: .openai)
        XCTAssertNotEqual(a, b)
    }

    func testPluginContextInequalityByCurrentQuery() {
        let a = PluginContext(sessionId: "s", messages: [], currentQuery: nil, model: "m", provider: .anthropic)
        let b = PluginContext(sessionId: "s", messages: [], currentQuery: "q", model: "m", provider: .anthropic)
        XCTAssertNotEqual(a, b)
    }

    func testPluginContextInequalityByMessages() {
        let msg = SDKMessage.assistant(.init(text: "hi", model: "m", stopReason: "end_turn"))
        let a = PluginContext(sessionId: "s", messages: [], model: "m", provider: .anthropic)
        let b = PluginContext(sessionId: "s", messages: [msg], model: "m", provider: .anthropic)
        XCTAssertNotEqual(a, b)
    }

    func testPluginContextWithMessages() {
        let msg = SDKMessage.assistant(.init(text: "hi", model: "m", stopReason: "end_turn"))
        let context = PluginContext(
            sessionId: "sess",
            messages: [msg],
            currentQuery: "q",
            model: "m",
            provider: .openai
        )
        XCTAssertEqual(context.messages.count, 1)
        XCTAssertEqual(context.provider, .openai)
    }

    // MARK: - PluginResult

    func testPluginResultNone() {
        let result = PluginResult.none
        XCTAssertEqual(result, PluginResult.none)
    }

    func testPluginResultSystemPromptBlock() {
        let result = PluginResult.systemPromptBlock("inject me")
        XCTAssertEqual(result, PluginResult.systemPromptBlock("inject me"))
        XCTAssertNotEqual(result, PluginResult.systemPromptBlock("other"))
        XCTAssertNotEqual(result, PluginResult.none)
    }

    func testPluginResultToolSchemas() {
        let schemas: [[String: Any]] = [
            ["type": "object", "properties": ["a": ["type": "string"]]]
        ]
        let result = PluginResult.toolSchemas(SendableToolSchemaList(schemas: schemas))
        let same = PluginResult.toolSchemas(SendableToolSchemaList(schemas: schemas))
        XCTAssertEqual(result, same)
    }

    func testPluginResultToolSchemasInequality() {
        let a = PluginResult.toolSchemas(SendableToolSchemaList(schemas: [["type": "object"]]))
        let b = PluginResult.toolSchemas(SendableToolSchemaList(schemas: [["type": "string"]]))
        XCTAssertNotEqual(a, b)
    }

    func testPluginResultToolSchemasDifferentCount() {
        let a = PluginResult.toolSchemas(SendableToolSchemaList(schemas: [["type": "object"]]))
        let b = PluginResult.toolSchemas(SendableToolSchemaList(schemas: []))
        XCTAssertNotEqual(a, b)
    }

    func testPluginResultFacts() {
        let signal = ExperienceSignal.create(
            domain: "test",
            kind: .observation,
            content: "learned something",
            confidence: 0.8,
            source: .conversation
        )
        let result = PluginResult.facts([signal])
        XCTAssertEqual(result, PluginResult.facts([signal]))
        XCTAssertNotEqual(result, PluginResult.none)
    }

    func testPluginResultCrossCaseInequality() {
        let signal = ExperienceSignal.create(
            domain: "test",
            kind: .observation,
            content: "x",
            confidence: 0.5,
            source: .conversation
        )
        let cases: [PluginResult] = [
            .none,
            .systemPromptBlock("prompt"),
            .toolSchemas(SendableToolSchemaList(schemas: [["type": "object"]])),
            .facts([signal]),
        ]
        for i in cases.indices {
            for j in cases.indices where i != j {
                XCTAssertNotEqual(cases[i], cases[j],
                    "PluginResult case \(i) should not equal case \(j)")
            }
        }
    }

    func testPluginResultFactsDifferentSignals() {
        let s1 = ExperienceSignal.create(domain: "a", kind: .observation, content: "x", confidence: 0.5, source: .conversation)
        let s2 = ExperienceSignal.create(domain: "b", kind: .observation, content: "y", confidence: 0.5, source: .conversation)
        XCTAssertNotEqual(PluginResult.facts([s1]), PluginResult.facts([s2]))
    }

    func testSendableToolSchemaListEmpty() {
        let empty = SendableToolSchemaList(schemas: [])
        let alsoEmpty = SendableToolSchemaList(schemas: [])
        XCTAssertEqual(empty, alsoEmpty)
    }

    // MARK: - SelfEvolutionPlugin Protocol

    func testMockPluginImplementsProtocol() async throws {
        let plugin = MockPlugin(
            name: "test",
            supportedPhases: [.syncTurn, .sessionEnd]
        )
        XCTAssertEqual(plugin.name, "test")
        XCTAssertEqual(plugin.supportedPhases, [.syncTurn, .sessionEnd])

        try await plugin.initialize(sessionId: "sess-1")
        XCTAssertEqual(plugin.initializedWith, "sess-1")

        let context = PluginContext(
            sessionId: "sess-1",
            messages: [],
            model: "m",
            provider: .anthropic
        )
        let result = try await plugin.onPhase(.syncTurn, context: context)
        XCTAssertEqual(result, .none)

        await plugin.shutdown()
        XCTAssertTrue(plugin.shutdownCalled)
    }

    func testPluginDefaultShutdown() async {
        let plugin = DefaultShutdownPlugin(name: "no-shutdown")
        await plugin.shutdown()
        // No crash = default implementation works
    }
}

// MARK: - Mock Implementations

private final class MockPlugin: SelfEvolutionPlugin, @unchecked Sendable {
    let name: String
    let supportedPhases: Set<PluginLifecyclePhase>
    var initializedWith: String?
    nonisolated(unsafe) var shutdownCalled = false

    init(name: String, supportedPhases: Set<PluginLifecyclePhase>) {
        self.name = name
        self.supportedPhases = supportedPhases
    }

    func initialize(sessionId: String) async throws {
        initializedWith = sessionId
    }

    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult {
        return .none
    }

    func shutdown() async {
        shutdownCalled = true
    }
}

private struct DefaultShutdownPlugin: SelfEvolutionPlugin {
    let name: String
    let supportedPhases: Set<PluginLifecyclePhase> = []

    func initialize(sessionId: String) async throws {}
    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult {
        return .none
    }
    // Intentionally NOT implementing shutdown() — tests default extension
}

// MARK: - AgentOptions.evolutionPlugins Integration (AC7/AC9)

extension PluginEvolutionTypesTests {

    func testAgentOptionsEvolutionPluginsDefaultNil() {
        let options = AgentOptions(apiKey: "test-key", model: "test")
        XCTAssertNil(options.evolutionPlugins, "evolutionPlugins should default to nil")
    }

    func testAgentOptionsEvolutionPluginsSetViaInit() {
        let configs = [
            EvolutionPluginConfig(name: "memory", enabled: true, config: ["store": "redis"]),
            EvolutionPluginConfig(name: "search", enabled: false),
        ]
        let options = AgentOptions(apiKey: "test-key", model: "test", evolutionPlugins: configs)
        XCTAssertEqual(options.evolutionPlugins?.count, 2)
        XCTAssertEqual(options.evolutionPlugins?[0].name, "memory")
        XCTAssertEqual(options.evolutionPlugins?[0].enabled, true)
        XCTAssertEqual(options.evolutionPlugins?[1].name, "search")
        XCTAssertEqual(options.evolutionPlugins?[1].enabled, false)
    }

    func testAgentOptionsEvolutionPluginsFromConfig() {
        let options = AgentOptions(from: SDKConfiguration())
        XCTAssertNil(options.evolutionPlugins, "evolutionPlugins should be nil when created from SDKConfiguration")
    }

    func testAgentOptionsEvolutionPluginsSinglePlugin() {
        let config = EvolutionPluginConfig(name: "optimizer")
        let options = AgentOptions(apiKey: "test-key", model: "test", evolutionPlugins: [config])
        XCTAssertEqual(options.evolutionPlugins?.count, 1)
        XCTAssertEqual(options.evolutionPlugins?.first?.name, "optimizer")
    }
}
