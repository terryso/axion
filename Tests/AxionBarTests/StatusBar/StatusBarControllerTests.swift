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

    // MARK: - Running State Management (Story 10.2)

    @Test("currentRunId starts nil")
    func currentRunIdStartsNil() {
        let controller = StatusBarController()
        #expect(controller.currentRunId == nil)
    }

    @Test("currentTask starts nil")
    func currentTaskStartsNil() {
        let controller = StatusBarController()
        #expect(controller.currentTask == nil)
    }

    @Test("currentStep starts at zero")
    func currentStepStartsZero() {
        let controller = StatusBarController()
        #expect(controller.currentStep == 0)
    }

    @Test("totalSteps starts at zero")
    func totalStepsStartsZero() {
        let controller = StatusBarController()
        #expect(controller.totalSteps == 0)
    }

    @Test("stepProgressText is nil when not running")
    func stepProgressTextNilWhenNotRunning() {
        let controller = StatusBarController()
        #expect(controller.stepProgressText == nil)
    }

    @Test("stepProgressText is nil when running but no task")
    func stepProgressTextNilWhenNoTask() {
        let controller = StatusBarController()
        controller.connectionState = .running
        #expect(controller.stepProgressText == nil)
    }

    @Test("stepProgressText shows progress when running")
    func stepProgressTextWhenRunning() {
        let controller = StatusBarController()
        controller.connectionState = .running
        controller.currentTask = "测试任务"
        controller.currentStep = 2
        controller.totalSteps = 5
        #expect(controller.stepProgressText == "步骤 2/5")
    }

    @Test("handleRunCompleted resets to connected state")
    func handleRunCompletedResetsToConnected() {
        let controller = StatusBarController()
        controller.connectionState = .running
        controller.currentRunId = "test-id"
        controller.currentTask = "测试"
        controller.currentStep = 3
        controller.totalSteps = 5

        controller.handleRunCompleted(finalStatus: "done")

        #expect(controller.connectionState == .connected)
        #expect(controller.currentStep == 0)
        #expect(controller.totalSteps == 0)
        #expect(controller.currentRunId == nil)
        #expect(controller.currentTask == nil)
    }

    @Test("services are initialized")
    func servicesInitialized() {
        let controller = StatusBarController()
        let _ = controller.taskSubmissionService
        let _ = controller.sseEventClient
        let _ = controller.runHistoryService
        let _ = controller.quickRunWindow
        let _ = controller.taskDetailPanel
        let _ = controller.runHistoryWindow
    }
}
