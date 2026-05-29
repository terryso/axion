import Testing
import Foundation
@testable import AxionCLI

@Suite("GatewayRunner + TelegramAdapter Integration")
struct GatewayTelegramIntegrationTests {

    // MARK: - Mock Server

    actor MockGatewayServer: GatewayHTTPControlling {
        private var continuation: CheckedContinuation<Void, Error>?

        func start() async throws {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
            }
        }

        func stop() async {
            let cont = continuation
            continuation = nil
            cont?.resume()
        }
    }

    // MARK: - tgStatus Provider (AC #7, Task 4.5)

    @Test("GatewayRunner tgStatus returns disabled before adapter starts")
    func tgStatusDisabledBeforeStart() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let mockAPI = MockTGAPIClient()
        await mockAPI.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mockAPI, allowedUsers: ["123"])

        await runner.setTelegramAdapter(adapter)
        await runner.setStatusProviders(
            tgStatus: { adapter.statusValue },
            reviewStatus: nil,
            curatorStatus: nil
        )

        let status = await runner.getStatus()
        #expect(status.tgConnected == "disabled")
    }

    @Test("GatewayRunner tgStatus reflects adapter error state")
    func tgStatusError() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let mockAPI = MockTGAPIClient()
        await mockAPI.setGetUpdatesError(TGAPIError.apiError("timeout"))
        let adapter = TelegramAdapter(apiClient: mockAPI, allowedUsers: [])

        await runner.setTelegramAdapter(adapter)
        await runner.setStatusProviders(
            tgStatus: { adapter.statusValue },
            reviewStatus: nil,
            curatorStatus: nil
        )

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        let status = await runner.getStatus()
        #expect(status.tgConnected?.hasPrefix("error:") == true)

        await adapter.stop()
    }

    @Test("GatewayRunner without provider has nil tgConnected")
    func noProviderNilTgStatus() async {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let status = await runner.getStatus()
        #expect(status.tgConnected == nil)
    }

    @Test("GatewayRunner stop also stops TelegramAdapter")
    func stopStopsTelegramAdapter() async throws {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        let mockAPI = MockTGAPIClient()
        await mockAPI.setUpdates([])
        let adapter = TelegramAdapter(apiClient: mockAPI, allowedUsers: [])

        await runner.setTelegramAdapter(adapter)

        let runnerTask = _Concurrency.Task { try await runner.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 50_000_000)

        _Concurrency.Task { await adapter.start() }
        try? await _Concurrency.Task.sleep(nanoseconds: 100_000_000)

        #expect(adapter.statusValue == "connected")

        await runner.stop(graceful: false)
        _ = await runnerTask.result

        #expect(adapter.statusValue == "disabled")
    }

    @Test("GatewayRunner with disabled tgStatus provider returns 'disabled'")
    func disabledTgStatus() async {
        let server = MockGatewayServer()
        let runner = GatewayRunner(server: server)

        await runner.setStatusProviders(
            tgStatus: { "disabled" },
            reviewStatus: nil,
            curatorStatus: nil
        )

        let status = await runner.getStatus()
        #expect(status.tgConnected == "disabled")
    }
}
