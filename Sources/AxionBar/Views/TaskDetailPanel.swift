import SwiftUI
import AppKit

@MainActor
final class TaskDetailPanel {
    private var window: NSWindow?

    func show(runId: String, task: String, controller: StatusBarController) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = TaskDetailView(runId: runId, task: task, controller: controller)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        newWindow.title = "任务详情 — \(task)"
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)

        self.window = newWindow
    }
}

struct TaskDetailView: View {
    let runId: String
    let task: String
    @ObservedObject var controller: StatusBarController

    @State private var logEntries: [LogEntry] = []
    @State private var isCompleted = false
    @State private var summaryText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task)
                .font(.headline)
                .lineLimit(2)

            if isCompleted, let summary = summaryText {
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(logEntries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: logEntries.count) {
                    if let last = logEntries.last {
                        proxy.scrollTo(last.id)
                    }
                }
            }
        }
        .padding()
        .onAppear {
            subscribeToEvents()
        }
        .onDisappear {
            controller.sseEventClient.disconnect()
        }
    }

    private func subscribeToEvents() {
        let stream = controller.sseEventClient.connect(runId: runId)

        Task {
            for await event in stream {
                switch event {
                case .stepStarted(let data):
                    let entry = LogEntry(
                        id: "started-\(data.stepIndex)",
                        text: "步骤 \(data.stepIndex + 1): \(data.tool) — 开始执行",
                        type: .started
                    )
                    logEntries.append(entry)

                case .stepCompleted(let data):
                    let icon = data.success ? "✓" : "✗"
                    let duration = data.durationMs.map { " (\($0)ms)" } ?? ""
                    let entry = LogEntry(
                        id: "completed-\(data.stepIndex)",
                        text: "\(icon) \(data.tool): \(data.purpose)\(duration)",
                        type: data.success ? .success : .failure
                    )
                    logEntries.append(entry)

                case .runCompleted(let data):
                    isCompleted = true
                    summaryText = "完成: \(data.totalSteps) 步, \(data.durationMs.map { "\($0)ms" } ?? "未知耗时"), 重规划 \(data.replanCount) 次"

                    controller.handleRunCompleted(finalStatus: data.finalStatus)
                }
            }
        }
    }
}

struct LogEntry: Identifiable {
    let id: String
    let text: String
    let type: EntryType

    enum EntryType {
        case started
        case success
        case failure
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 4)

            Text(entry.text)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(textColor)
        }
    }

    private var color: Color {
        switch entry.type {
        case .started: return .blue
        case .success: return .green
        case .failure: return .red
        }
    }

    private var textColor: Color {
        switch entry.type {
        case .started: return .primary
        case .success: return .primary
        case .failure: return .red
        }
    }
}
