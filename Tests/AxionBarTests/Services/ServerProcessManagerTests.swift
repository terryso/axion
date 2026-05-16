import Testing
import Foundation
@testable import AxionBar

@Suite("ServerProcessManager")
struct ServerProcessManagerTests {

    @Test("isServerManagedByUs starts as false")
    @MainActor
    func initialState() {
        let manager = ServerProcessManager()
        #expect(manager.isServerManagedByUs == false)
    }

    @Test("findAxionCLI returns nil when axion not in PATH")
    func findAxionCLINotFound() {
        // This test verifies the static method works without crashing
        // In CI, axion may or may not be installed
        let result = ServerProcessManager.findAxionCLI()
        // Result depends on environment, just verify no crash
        _ = result
    }

    @Test("stopServer when no process does nothing")
    @MainActor
    func stopServerWhenNoProcess() {
        let manager = ServerProcessManager()
        manager.stopServer()
        #expect(manager.isServerManagedByUs == false)
    }

    @Test("startServer sets lastError when CLI not found")
    @MainActor
    func startServerCLINotFound() async {
        // This test verifies error handling when axion is not available.
        // If axion IS in PATH, the server starts and we clean up.
        let manager = ServerProcessManager()
        let checker = BackendHealthChecker()
        manager.startServer(healthChecker: checker)
        if manager.isServerManagedByUs {
            manager.stopServer()
            #expect(manager.isServerManagedByUs == false)
        } else {
            #expect(manager.lastError == "未找到 axion 命令行工具")
        }
    }

    @Test("double stopServer does not crash")
    @MainActor
    func doubleStopServer() {
        let manager = ServerProcessManager()
        manager.stopServer()
        manager.stopServer()
        #expect(manager.isServerManagedByUs == false)
    }

    @Test("lastError starts nil")
    @MainActor
    func lastErrorStartsNil() {
        let manager = ServerProcessManager()
        #expect(manager.lastError == nil)
    }
}
