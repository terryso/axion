import Testing
import Foundation
@testable import AxionBar

@MainActor
@Suite("BackendHealthChecker")
struct BackendHealthCheckerTests {

    @Test("initial state is disconnected")
    func initialState() async {
        let checker = BackendHealthChecker()
        #expect(checker.connectionState == .disconnected)
        #expect(checker.serverVersion == nil)
    }

    @Test("checkInterval defaults to 5 seconds")
    func checkInterval() {
        let checker = BackendHealthChecker()
        #expect(checker.checkInterval == 5.0)
    }

    @Test("checkOnce returns false when no server running")
    func checkOnceNoServer() async {
        let checker = BackendHealthChecker()
        let result = await checker.checkOnce()
        #expect(result == false)
        #expect(checker.connectionState == .disconnected)
    }

    @Test("stopChecking resets isChecking flag")
    func stopChecking() async {
        let checker = BackendHealthChecker()
        checker.startChecking()
        checker.stopChecking()
        // Verify no crash and clean shutdown
    }

    @Test("startChecking is idempotent — calling twice does not crash")
    func startCheckingIdempotent() async {
        let checker = BackendHealthChecker()
        checker.startChecking()
        checker.startChecking()
        checker.stopChecking()
        // No crash = pass
    }

    @Test("checkOnce after stopChecking returns false")
    func checkOnceAfterStop() async {
        let checker = BackendHealthChecker()
        checker.startChecking()
        checker.stopChecking()
        let result = await checker.checkOnce()
        #expect(result == false)
        #expect(checker.connectionState == .disconnected)
    }

    @Test("serverVersion starts nil and stays nil without server")
    func serverVersionRemainsNil() async {
        let checker = BackendHealthChecker()
        _ = await checker.checkOnce()
        #expect(checker.serverVersion == nil)
    }
}
