import SwiftUI
import Combine
import UserNotifications
import os.log

@MainActor
final class StatusBarController: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var serverVersion: String?
    @Published var currentRunId: String?
    @Published var currentTask: String?
    @Published var currentStep: Int = 0
    @Published var totalSteps: Int = 0

    private let healthChecker = BackendHealthChecker()
    private let processManager = ServerProcessManager()
    private let logger = Logger(subsystem: "com.axion.AxionBar", category: "StatusBarController")

    let taskSubmissionService = TaskSubmissionService()
    let sseEventClient = SSEEventClient()
    let runHistoryService = RunHistoryService()

    let quickRunWindow = QuickRunWindow()
    let taskDetailPanel = TaskDetailPanel()
    let runHistoryWindow = RunHistoryWindow()

    // Separate SSE client for internal run monitoring (independent from view subscriptions)
    private let monitoringSSEClient = SSEEventClient()
    private var runMonitoringTask: Task<Void, Never>?

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

    init() {
        healthChecker.$connectionState
            .assign(to: &$connectionState)

        healthChecker.$serverVersion
            .assign(to: &$serverVersion)

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
    }

    private func sendNotification(title: String, body: String) {
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
