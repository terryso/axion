import XCTest
@testable import OpenAgentSDK

final class PluginRegistryTests: XCTestCase {

    private func makeContext() -> PluginContext {
        PluginContext(
            sessionId: "test-session",
            messages: [],
            currentQuery: nil,
            model: "test-model",
            provider: .anthropic
        )
    }

    // MARK: - Register / Unregister

    func testRegisterAndGetPlugin() async throws {
        let registry = PluginRegistry()
        let plugin = TrackingPlugin(name: "p1", supportedPhases: [.syncTurn])
        try await registry.register(plugin)

        let retrieved = await registry.getPlugin(name: "p1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "p1")
    }

    func testRegisterDuplicateThrows() async throws {
        let registry = PluginRegistry()
        try await registry.register(TrackingPlugin(name: "dup", supportedPhases: []))
        do {
            try await registry.register(TrackingPlugin(name: "dup", supportedPhases: []))
            XCTFail("Expected duplicate registration to throw")
        } catch let error as SDKError {
            if case .invalidConfiguration(let msg) = error {
                XCTAssertTrue(msg.contains("dup"), "Error message should mention plugin name")
            } else {
                XCTFail("Expected invalidConfiguration error")
            }
        }
    }

    func testUnregister() async throws {
        let registry = PluginRegistry()
        try await registry.register(TrackingPlugin(name: "to-remove", supportedPhases: []))
        let namesBefore = await registry.pluginNames
        XCTAssertEqual(namesBefore, ["to-remove"])

        await registry.unregister(name: "to-remove")
        let retrieved = await registry.getPlugin(name: "to-remove")
        XCTAssertNil(retrieved)
        let namesAfter = await registry.pluginNames
        XCTAssertTrue(namesAfter.isEmpty)
    }

    func testUnregisterNonexistent() async {
        let registry = PluginRegistry()
        // Should not crash
        await registry.unregister(name: "ghost")
    }

    func testGetPluginNonexistent() async {
        let registry = PluginRegistry()
        let result = await registry.getPlugin(name: "nope")
        XCTAssertNil(result)
    }

    func testAllPlugins() async throws {
        let registry = PluginRegistry()
        try await registry.register(TrackingPlugin(name: "a", supportedPhases: []))
        try await registry.register(TrackingPlugin(name: "b", supportedPhases: []))

        let all = await registry.allPlugins()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].name, "a")
        XCTAssertEqual(all[1].name, "b")
    }

    func testPluginNames() async throws {
        let registry = PluginRegistry()
        try await registry.register(TrackingPlugin(name: "alpha", supportedPhases: []))
        try await registry.register(TrackingPlugin(name: "beta", supportedPhases: []))

        let names = await registry.pluginNames
        XCTAssertEqual(names, ["alpha", "beta"])
    }

    // MARK: - Dispatch

    func testDispatchesToCorrectPhasesOnly() async throws {
        let registry = PluginRegistry()
        let syncPlugin = TrackingPlugin(name: "sync-only", supportedPhases: [.syncTurn])
        let endPlugin = TrackingPlugin(name: "end-only", supportedPhases: [.sessionEnd])
        try await registry.register(syncPlugin)
        try await registry.register(endPlugin)

        let context = makeContext()
        _ = await registry.dispatch(.syncTurn, context: context)

        XCTAssertEqual(syncPlugin.phaseCallCount[.syncTurn], 1)
        XCTAssertNil(syncPlugin.phaseCallCount[.sessionEnd])
        XCTAssertNil(endPlugin.phaseCallCount[.syncTurn])
        XCTAssertNil(endPlugin.phaseCallCount[.sessionEnd])
    }

    func testDispatchReturnsResults() async throws {
        let registry = PluginRegistry()
        let plugin = ResultPlugin(name: "resulter", supportedPhases: [.syncTurn], result: .systemPromptBlock("injected"))
        try await registry.register(plugin)

        let results = await registry.dispatch(.syncTurn, context: makeContext())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0], .systemPromptBlock("injected"))
    }

    func testDispatchEmptyWhenNoPluginsSupportPhase() async throws {
        let registry = PluginRegistry()
        try await registry.register(TrackingPlugin(name: "p", supportedPhases: [.syncTurn]))

        let results = await registry.dispatch(.prefetch, context: makeContext())
        XCTAssertTrue(results.isEmpty)
    }

    func testDispatchErrorIsolation() async throws {
        let registry = PluginRegistry()
        let failingPlugin = FailingPlugin(name: "fails", supportedPhases: [.syncTurn])
        let goodPlugin = ResultPlugin(name: "good", supportedPhases: [.syncTurn], result: .none)
        try await registry.register(failingPlugin)
        try await registry.register(goodPlugin)

        // failingPlugin throws, goodPlugin should still run
        let results = await registry.dispatch(.syncTurn, context: makeContext())
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], .none) // failingPlugin produces .none fallback
        XCTAssertEqual(results[1], .none) // goodPlugin produces .none
    }

    // MARK: - InitializeAll

    func testInitializeAllOrder() async throws {
        let registry = PluginRegistry()
        let plugin1 = TrackingPlugin(name: "first", supportedPhases: [])
        let plugin2 = TrackingPlugin(name: "second", supportedPhases: [])
        try await registry.register(plugin1)
        try await registry.register(plugin2)

        try await registry.initializeAll(sessionId: "sess")
        XCTAssertEqual(plugin1.initializedWith, "sess")
        XCTAssertEqual(plugin2.initializedWith, "sess")
    }

    func testInitializeAllCollectsErrors() async throws {
        let registry = PluginRegistry()
        let good = TrackingPlugin(name: "good", supportedPhases: [])
        let bad = FailingInitPlugin(name: "bad-init")
        try await registry.register(good)
        try await registry.register(bad)

        do {
            try await registry.initializeAll(sessionId: "sess")
            XCTFail("Expected error from failing init")
        } catch let error as SDKError {
            if case .invalidConfiguration(let msg) = error {
                XCTAssertTrue(msg.contains("bad-init"), "Error should mention failing plugin name")
            } else {
                XCTFail("Expected invalidConfiguration error, got \(error)")
            }
        }
        // good plugin should still have been initialized
        XCTAssertEqual(good.initializedWith, "sess")
    }

    // MARK: - ShutdownAll

    func testShutdownAllReverseOrder() async throws {
        let registry = PluginRegistry()
        let state = SharedOrderCapture()
        let p1 = OrderTrackingPlugin(name: "p1", state: state)
        let p2 = OrderTrackingPlugin(name: "p2", state: state)
        let p3 = OrderTrackingPlugin(name: "p3", state: state)
        try await registry.register(p1)
        try await registry.register(p2)
        try await registry.register(p3)

        await registry.shutdownAll()
        XCTAssertEqual(state.shutdownOrder, ["p3", "p2", "p1"])
    }

    // MARK: - Edge Cases

    func testDispatchWithNoPlugins() async {
        let registry = PluginRegistry()
        let results = await registry.dispatch(.syncTurn, context: makeContext())
        XCTAssertTrue(results.isEmpty, "Dispatch on empty registry should return empty results")
    }

    func testReRegisterAfterUnregister() async throws {
        let registry = PluginRegistry()
        try await registry.register(TrackingPlugin(name: "x", supportedPhases: [.syncTurn]))
        await registry.unregister(name: "x")
        // Should succeed — plugin was removed
        try await registry.register(TrackingPlugin(name: "x", supportedPhases: [.prefetch]))
        let names = await registry.pluginNames
        XCTAssertEqual(names, ["x"])
    }

    func testDispatchMultiplePhases() async throws {
        let registry = PluginRegistry()
        let plugin = TrackingPlugin(name: "multi", supportedPhases: [.prefetch, .syncTurn, .sessionEnd])
        try await registry.register(plugin)

        let context = makeContext()
        _ = await registry.dispatch(.prefetch, context: context)
        _ = await registry.dispatch(.syncTurn, context: context)
        _ = await registry.dispatch(.sessionEnd, context: context)

        XCTAssertEqual(plugin.phaseCallCount[.prefetch], 1)
        XCTAssertEqual(plugin.phaseCallCount[.syncTurn], 1)
        XCTAssertEqual(plugin.phaseCallCount[.sessionEnd], 1)
    }

    func testDispatchCollectsMixedResults() async throws {
        let registry = PluginRegistry()
        try await registry.register(ResultPlugin(name: "r1", supportedPhases: [.syncTurn], result: .systemPromptBlock("a")))
        try await registry.register(ResultPlugin(name: "r2", supportedPhases: [.syncTurn], result: .none))
        try await registry.register(ResultPlugin(name: "r3", supportedPhases: [.syncTurn], result: .facts([
            ExperienceSignal.create(domain: "d", kind: .observation, content: "c", confidence: 0.9, source: .conversation)
        ])))

        let results = await registry.dispatch(.syncTurn, context: makeContext())
        XCTAssertEqual(results.count, 3)

        if case .systemPromptBlock(let text) = results[0] {
            XCTAssertEqual(text, "a")
        } else {
            XCTFail("Expected systemPromptBlock")
        }
        XCTAssertEqual(results[1], .none)
        if case .facts(let signals) = results[2] {
            XCTAssertEqual(signals.count, 1)
        } else {
            XCTFail("Expected facts")
        }
    }

    // MARK: - E2E: Full Lifecycle Integration

    func testFullPluginLifecycle() async throws {
        let registry = PluginRegistry()

        // 1. Register two plugins
        let lifecyclePlugin = LifecycleTrackingPlugin(name: "lifecycle", supportedPhases: [.prefetch, .syncTurn, .sessionEnd])
        let promptPlugin = PromptInjectPlugin(name: "prompt-inject", supportedPhases: [.syncTurn])
        try await registry.register(lifecyclePlugin)
        try await registry.register(promptPlugin)

        // 2. Initialize all
        try await registry.initializeAll(sessionId: "e2e-session")
        XCTAssertEqual(lifecyclePlugin.initializedWith, "e2e-session")
        XCTAssertEqual(promptPlugin.initializedWith, "e2e-session")

        // 3. Dispatch prefetch (only lifecycle plugin supports it)
        let prefetchResults = await registry.dispatch(.prefetch, context: makeContext())
        XCTAssertEqual(prefetchResults.count, 1)
        XCTAssertEqual(prefetchResults[0], .none)
        XCTAssertEqual(lifecyclePlugin.phaseCallCount[.prefetch], 1)
        XCTAssertNil(promptPlugin.phaseCallCount[.prefetch])

        // 4. Dispatch syncTurn (both plugins support it)
        let syncResults = await registry.dispatch(.syncTurn, context: makeContext())
        XCTAssertEqual(syncResults.count, 2)
        XCTAssertEqual(syncResults[0], .none) // lifecycle plugin
        XCTAssertEqual(syncResults[1], .systemPromptBlock("injected-context")) // prompt plugin
        XCTAssertEqual(lifecyclePlugin.phaseCallCount[.syncTurn], 1)
        XCTAssertEqual(promptPlugin.phaseCallCount[.syncTurn], 1)

        // 5. Dispatch sessionEnd (only lifecycle plugin supports it)
        let endResults = await registry.dispatch(.sessionEnd, context: makeContext())
        XCTAssertEqual(endResults.count, 1)
        XCTAssertEqual(lifecyclePlugin.phaseCallCount[.sessionEnd], 1)

        // 6. Shutdown all (reverse order)
        let shutdownState = SharedOrderCapture()
        let shutdownP1 = OrderTrackingPlugin(name: "sp1", state: shutdownState)
        let shutdownP2 = OrderTrackingPlugin(name: "sp2", state: shutdownState)
        try await registry.register(shutdownP1)
        try await registry.register(shutdownP2)

        await registry.shutdownAll()
        // sp2, sp1 are last two registered — shutdown order is sp2, sp1
        let names = shutdownState.shutdownOrder
        XCTAssertEqual(names.suffix(2), ["sp2", "sp1"])
    }
}

// MARK: - Mock Plugins

private final class TrackingPlugin: SelfEvolutionPlugin, @unchecked Sendable {
    let name: String
    let supportedPhases: Set<PluginLifecyclePhase>
    var initializedWith: String?
    nonisolated(unsafe) var phaseCallCount: [PluginLifecyclePhase: Int] = [:]

    init(name: String, supportedPhases: Set<PluginLifecyclePhase>) {
        self.name = name
        self.supportedPhases = supportedPhases
    }

    func initialize(sessionId: String) async throws {
        initializedWith = sessionId
    }

    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult {
        phaseCallCount[phase, default: 0] += 1
        return .none
    }
}

private struct ResultPlugin: SelfEvolutionPlugin {
    let name: String
    let supportedPhases: Set<PluginLifecyclePhase>
    let result: PluginResult

    func initialize(sessionId: String) async throws {}
    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult {
        result
    }
}

private struct FailingPlugin: SelfEvolutionPlugin {
    let name: String
    let supportedPhases: Set<PluginLifecyclePhase>

    func initialize(sessionId: String) async throws {}
    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult {
        throw SDKError.invalidConfiguration("Intentional failure for testing")
    }
}

private struct FailingInitPlugin: SelfEvolutionPlugin {
    let name: String
    let supportedPhases: Set<PluginLifecyclePhase> = []

    func initialize(sessionId: String) async throws {
        throw SDKError.invalidConfiguration("Init failure for testing")
    }
    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult {
        .none
    }
}

private final class SharedOrderCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _order: [String] = []

    var shutdownOrder: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _order
    }

    func record(_ name: String) {
        lock.lock()
        _order.append(name)
        lock.unlock()
    }
}

private struct OrderTrackingPlugin: SelfEvolutionPlugin {
    let name: String
    let supportedPhases: Set<PluginLifecyclePhase> = []
    let state: SharedOrderCapture

    func initialize(sessionId: String) async throws {}
    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult { .none }
    func shutdown() async {
        state.record(name)
    }
}

private final class LifecycleTrackingPlugin: SelfEvolutionPlugin, @unchecked Sendable {
    let name: String
    let supportedPhases: Set<PluginLifecyclePhase>
    var initializedWith: String?
    nonisolated(unsafe) var phaseCallCount: [PluginLifecyclePhase: Int] = [:]

    init(name: String, supportedPhases: Set<PluginLifecyclePhase>) {
        self.name = name
        self.supportedPhases = supportedPhases
    }

    func initialize(sessionId: String) async throws {
        initializedWith = sessionId
    }

    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult {
        phaseCallCount[phase, default: 0] += 1
        return .none
    }
}

private final class PromptInjectPlugin: SelfEvolutionPlugin, @unchecked Sendable {
    let name: String
    let supportedPhases: Set<PluginLifecyclePhase>
    var initializedWith: String?
    nonisolated(unsafe) var phaseCallCount: [PluginLifecyclePhase: Int] = [:]

    init(name: String, supportedPhases: Set<PluginLifecyclePhase>) {
        self.name = name
        self.supportedPhases = supportedPhases
    }

    func initialize(sessionId: String) async throws {
        initializedWith = sessionId
    }

    func onPhase(_ phase: PluginLifecyclePhase, context: PluginContext) async throws -> PluginResult {
        phaseCallCount[phase, default: 0] += 1
        return .systemPromptBlock("injected-context")
    }
}
