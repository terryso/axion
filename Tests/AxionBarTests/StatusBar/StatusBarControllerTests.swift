import Testing
@testable import AxionBar

@MainActor
@Suite("StatusBarController")
struct StatusBarControllerTests {

    @Test("initial state is disconnected")
    func initialState() {
        let controller = StatusBarController()
        #expect(controller.connectionState == .disconnected)
        #expect(controller.serverVersion == nil)
    }

    @Test("statusIcon maps disconnected to circle.dashed")
    func statusIconDisconnected() {
        let controller = StatusBarController()
        #expect(controller.statusIcon == "circle.dashed")
    }

    @Test("statusTooltip maps disconnected")
    func statusTooltipDisconnected() {
        let controller = StatusBarController()
        #expect(controller.statusTooltip == "Axion — 未连接")
    }

    @Test("isServerManagedByUs starts false")
    func isServerManagedByUs() {
        let controller = StatusBarController()
        #expect(controller.isServerManagedByUs == false)
    }

    @Test("statusIcon maps connected to circle.fill")
    func statusIconConnected() {
        let controller = StatusBarController()
        controller.connectionState = .connected
        #expect(controller.statusIcon == "circle.fill")
    }

    @Test("statusIcon maps running to circle.circle")
    func statusIconRunning() {
        let controller = StatusBarController()
        controller.connectionState = .running
        #expect(controller.statusIcon == "circle.circle")
    }

    @Test("statusTooltip maps connected")
    func statusTooltipConnected() {
        let controller = StatusBarController()
        controller.connectionState = .connected
        #expect(controller.statusTooltip == "Axion — 就绪")
    }

    @Test("statusTooltip maps running")
    func statusTooltipRunning() {
        let controller = StatusBarController()
        controller.connectionState = .running
        #expect(controller.statusTooltip == "Axion — 运行中")
    }

    @Test("serverVersion can be set")
    func serverVersionSettable() {
        let controller = StatusBarController()
        controller.serverVersion = "2.0.1"
        #expect(controller.serverVersion == "2.0.1")
    }

    @Test("state transition from disconnected to connected updates icon")
    func stateTransitionIcon() {
        let controller = StatusBarController()
        #expect(controller.statusIcon == "circle.dashed")
        controller.connectionState = .connected
        #expect(controller.statusIcon == "circle.fill")
        controller.connectionState = .running
        #expect(controller.statusIcon == "circle.circle")
        controller.connectionState = .disconnected
        #expect(controller.statusIcon == "circle.dashed")
    }
}
