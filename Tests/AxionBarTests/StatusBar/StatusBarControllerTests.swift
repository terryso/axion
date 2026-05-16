import Testing
@testable import AxionBar

final class MockNotificationSender: NotificationSending {
    var lastTitle: String?
    var lastBody: String?
    var sendCount = 0

    func send(title: String, body: String) {
        lastTitle = title
        lastBody = body
        sendCount += 1
    }
}

@MainActor
@Suite("StatusBarController")
struct StatusBarControllerTests {

    private func makeController(sender: MockNotificationSender = MockNotificationSender()) -> StatusBarController {
        StatusBarController(notificationSender: sender)
    }

    @Test("initial state is disconnected")
    func initialState() {
        let controller = makeController()
        #expect(controller.connectionState == .disconnected)
        #expect(controller.serverVersion == nil)
    }

    @Test("statusIcon maps disconnected to circle.dashed")
    func statusIconDisconnected() {
        let controller = makeController()
        #expect(controller.statusIcon == "circle.dashed")
    }

    @Test("statusTooltip maps disconnected")
    func statusTooltipDisconnected() {
        let controller = makeController()
        #expect(controller.statusTooltip == "Axion — 未连接")
    }

    @Test("isServerManagedByUs starts false")
    func isServerManagedByUs() {
        let controller = makeController()
        #expect(controller.isServerManagedByUs == false)
    }

    @Test("statusIcon maps connected to circle.fill")
    func statusIconConnected() {
        let controller = makeController()
        controller.connectionState = .connected
        #expect(controller.statusIcon == "circle.fill")
    }

    @Test("statusIcon maps running to circle.circle")
    func statusIconRunning() {
        let controller = makeController()
        controller.connectionState = .running
        #expect(controller.statusIcon == "circle.circle")
    }

    @Test("statusTooltip maps connected")
    func statusTooltipConnected() {
        let controller = makeController()
        controller.connectionState = .connected
        #expect(controller.statusTooltip == "Axion — 就绪")
    }

    @Test("statusTooltip maps running")
    func statusTooltipRunning() {
        let controller = makeController()
        controller.connectionState = .running
        #expect(controller.statusTooltip == "Axion — 运行中")
    }

    @Test("serverVersion can be set")
    func serverVersionSettable() {
        let controller = makeController()
        controller.serverVersion = "2.0.1"
        #expect(controller.serverVersion == "2.0.1")
    }

    @Test("state transition from disconnected to connected updates icon")
    func stateTransitionIcon() {
        let controller = makeController()
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
        let controller = makeController()
        #expect(controller.currentRunId == nil)
    }

    @Test("currentTask starts nil")
    func currentTaskStartsNil() {
        let controller = makeController()
        #expect(controller.currentTask == nil)
    }

    @Test("currentStep starts at zero")
    func currentStepStartsZero() {
        let controller = makeController()
        #expect(controller.currentStep == 0)
    }

    @Test("totalSteps starts at zero")
    func totalStepsStartsZero() {
        let controller = makeController()
        #expect(controller.totalSteps == 0)
    }

    @Test("stepProgressText is nil when not running")
    func stepProgressTextNilWhenNotRunning() {
        let controller = makeController()
        #expect(controller.stepProgressText == nil)
    }

    @Test("stepProgressText is nil when running but no task")
    func stepProgressTextNilWhenNoTask() {
        let controller = makeController()
        controller.connectionState = .running
        #expect(controller.stepProgressText == nil)
    }

    @Test("stepProgressText shows progress when running")
    func stepProgressTextWhenRunning() {
        let controller = makeController()
        controller.connectionState = .running
        controller.currentTask = "测试任务"
        controller.currentStep = 2
        controller.totalSteps = 5
        #expect(controller.stepProgressText == "步骤 2/5")
    }

    @Test("handleRunCompleted resets to connected state")
    func handleRunCompletedResetsToConnected() {
        let sender = MockNotificationSender()
        let controller = makeController(sender: sender)
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
        #expect(sender.lastTitle == "任务完成")
        #expect(sender.lastBody == "测试")
    }

    @Test("services are initialized")
    func servicesInitialized() {
        let controller = makeController()
        let _ = controller.taskSubmissionService
        let _ = controller.sseEventClient
        let _ = controller.runHistoryService
        let _ = controller.skillService
        let _ = controller.quickRunWindow
        let _ = controller.taskDetailPanel
        let _ = controller.runHistoryWindow
        let _ = controller.settingsWindow
        let _ = controller.hotkeyConfigManager
        let _ = controller.hotkeyService
    }

    // MARK: - Skill Management (Story 10.3)

    @Test("availableSkills starts empty")
    func availableSkillsStartsEmpty() {
        let controller = makeController()
        #expect(controller.availableSkills.isEmpty)
    }

    @Test("loadSkills does nothing when disconnected")
    func loadSkillsDisconnected() async {
        let controller = makeController()
        controller.connectionState = .disconnected
        await controller.loadSkills()
        #expect(controller.availableSkills.isEmpty)
    }
}
