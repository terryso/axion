import SwiftUI
import Combine
import UserNotifications
import os.log

protocol NotificationSending {
    func send(title: String, body: String)
}

final class UserNotificationSender: NotificationSending {
    func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
final class StatusBarController: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var serverVersion: String?
    @Published var currentRunId: String?
    @Published var currentTask: String?
    @Published var currentStep: Int = 0
    @Published var totalSteps: Int = 0
    @Published var availableSkills: [BarSkillSummary] = []

    private let healthChecker = BackendHealthChecker()
    private let processManager = ServerProcessManager()
    let notificationSender: NotificationSending
    private let logger = Logger(subsystem: "com.axion.AxionBar", category: "StatusBarController")

    let taskSubmissionService = TaskSubmissionService()
    let sseEventClient = SSEEventClient()
    let runHistoryService = RunHistoryService()
    let skillService = SkillService()

    let quickRunWindow = QuickRunWindow()
    let taskDetailPanel = TaskDetailPanel()
    let runHistoryWindow = RunHistoryWindow()
    let settingsWindow = SettingsWindow()

    let hotkeyConfigManager = HotkeyConfigManager()
    let hotkeyService = GlobalHotkeyService()

    // Separate SSE client for internal run monitoring (independent from view subscriptions)
    private let monitoringSSEClient = SSEEventClient()
    private var runMonitoringTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var statusIcon: String {
        switch connectionState {
        case .disconnected:
            return "circle.dashed"
        case .connected:
            return "circle.fill"
        case .running:
            return "circle.circle"
        }
    }

    var statusTooltip: String {
        switch connectionState {
        case .disconnected:
            return "Axion — 未连接"
        case .connected:
            return "Axion — 就绪"
        case .running:
            return "Axion — 运行中"
        }
    }

    var stepProgressText: String? {
        guard connectionState == .running, currentTask != nil else { return nil }
        return "步骤 \(currentStep)/\(totalSteps)"
    }

    init(notificationSender: NotificationSending = UserNotificationSender()) {
        self.notificationSender = notificationSender
        healthChecker.$connectionState
            .assign(to: &$connectionState)

        healthChecker.$serverVersion
            .assign(to: &$serverVersion)

        // Load hotkey config
        hotkeyConfigManager.load()
        hotkeyService.onHotkeyTriggered = { [weak self] binding in
            self?.handleHotkeyTriggered(binding)
        }
        hotkeyService.start(configManager: hotkeyConfigManager)

        // Watch for connection state changes to load skills
        $connectionState
            .removeDuplicates()
            .sink { [weak self] state in
                if state == .connected {
                    Task { await self?.loadSkills() }
                } else if state == .disconnected {
                    self?.availableSkills = []
                }
            }
            .store(in: &cancellables)

        startHealthChecking()
    }

    func startHealthChecking() {
        healthChecker.startChecking()
    }

    func startServer() {
        processManager.startServer(healthChecker: healthChecker)
    }

    func stopServer() {
        processManager.stopServer()
    }

    var isServerManagedByUs: Bool {
        processManager.isServerManagedByUs
    }

    // MARK: - Task Management

    func submitTask(task: String) async throws -> BarCreateRunResponse {
        try await taskSubmissionService.submit(task: task)
    }

    func startRunMonitoring(runId: String) {
        runMonitoringTask?.cancel()
        monitoringSSEClient.disconnect()

        runMonitoringTask = Task { [weak self] in
            guard let self else { return }

            let stream = self.monitoringSSEClient.connect(runId: runId)
            for await event in stream {
                guard !Task.isCancelled else { return }

                switch event {
                case .stepStarted(let data):
                    self.currentStep = data.stepIndex + 1

                case .stepCompleted(let data):
                    self.currentStep = data.stepIndex + 1

                case .runCompleted(let data):
                    self.totalSteps = data.totalSteps
                    self.handleRunCompleted(finalStatus: data.finalStatus)
                    return
                }
            }

            // Stream ended without run_completed (connection lost while running)
            if self.connectionState == .running {
                self.logger.warning("SSE stream ended unexpectedly for runId: \(runId)")
                self.handleRunCompleted(finalStatus: "unknown")
            }
        }
    }

    func handleRunCompleted(finalStatus: String) {
        let taskName = currentTask ?? "任务"

        let title = finalStatus == "done" ? "任务完成" : "任务失败"
        let body = taskName

        sendNotification(title: title, body: body)

        connectionState = .connected
        currentStep = 0
        totalSteps = 0
        currentRunId = nil
        currentTask = nil

        runMonitoringTask?.cancel()
        runMonitoringTask = nil
        monitoringSSEClient.disconnect()
        sseEventClient.disconnect()

        // Reload skills after run completes
        Task { await loadSkills() }
    }

    // MARK: - Skill Management

    func loadSkills() async {
        guard connectionState != .disconnected else { return }
        do {
            availableSkills = try await skillService.fetchSkills()
        } catch {
            logger.debug("Failed to load skills: \(error.localizedDescription)")
        }
    }

    func runSkill(name: String) async {
        guard connectionState != .disconnected else { return }
        do {
            let response = try await skillService.runSkill(name: name)
            currentRunId = response.runId
            currentTask = "技能: \(name)"
            connectionState = .running
            startRunMonitoring(runId: response.runId)
        } catch {
            logger.error("Failed to run skill '\(name)': \(error.localizedDescription)")
        }
    }

    // MARK: - Hotkey Management

    func restartHotkeyService() {
        hotkeyService.start(configManager: hotkeyConfigManager)
    }

    private func handleHotkeyTriggered(_ binding: HotkeyBinding) {
        switch binding.action {
        case .skill(let name):
            Task { await runSkill(name: name) }
        case .task(let description):
            Task {
                do {
                    let response = try await submitTask(task: description)
                    currentRunId = response.runId
                    currentTask = description
                    connectionState = .running
                    startRunMonitoring(runId: response.runId)
                } catch {
                    logger.error("Hotkey task submission failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func sendNotification(title: String, body: String) {
        notificationSender.send(title: title, body: body)
    }
}
