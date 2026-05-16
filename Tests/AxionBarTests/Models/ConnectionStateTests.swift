import Testing
@testable import AxionBar

@Suite("ConnectionState")
struct ConnectionStateTests {

    @Test("disconnected raw value")
    func disconnectedRawValue() {
        #expect(ConnectionState.disconnected.rawValue == "disconnected")
    }

    @Test("connected raw value")
    func connectedRawValue() {
        #expect(ConnectionState.connected.rawValue == "connected")
    }

    @Test("running raw value")
    func runningRawValue() {
        #expect(ConnectionState.running.rawValue == "running")
    }

    @Test("init from raw value")
    func initFromRawValue() {
        #expect(ConnectionState(rawValue: "connected") == .connected)
        #expect(ConnectionState(rawValue: "disconnected") == .disconnected)
        #expect(ConnectionState(rawValue: "running") == .running)
        #expect(ConnectionState(rawValue: "unknown") == nil)
    }

    @Test("all three cases are distinct")
    func distinctCases() {
        let all: [ConnectionState] = [.disconnected, .connected, .running]
        let unique = Set(all)
        #expect(unique.count == 3)
    }
}
