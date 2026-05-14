import SwiftUI
import AppKit

@MainActor
final class RunHistoryWindow {
    private var window: NSWindow?

    func show(controller: StatusBarController) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = RunHistoryListView(controller: controller)

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        newWindow.title = "任务历史"
        newWindow.contentView = NSHostingView(rootView: contentView)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)

        self.window = newWindow
    }
}

struct RunHistoryListView: View {
    @ObservedObject var controller: StatusBarController

    @State private var runs: [BarRunStatusResponse] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Text("加载失败")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else if runs.isEmpty {
                Spacer()
                Text("暂无任务记录")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(runs, id: \.runId) { run in
                    RunHistoryRow(run: run)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openDetail(run: run)
                        }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            loadHistory()
        }
    }

    private func loadHistory() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                runs = try await controller.runHistoryService.fetchHistory(limit: 20)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func openDetail(run: BarRunStatusResponse) {
        controller.currentRunId = run.runId
        controller.currentTask = run.task
        controller.taskDetailPanel.show(runId: run.runId, task: run.task, controller: controller)
    }
}

struct RunHistoryRow: View {
    let run: BarRunStatusResponse

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.task)
                    .lineLimit(1)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(run.submittedAt)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let duration = run.durationMs {
                        Text("\(duration)ms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            statusBadge(run.status)
        }
        .padding(.vertical, 2)
    }

    private func statusBadge(_ status: String) -> some View {
        let color: Color = switch status {
        case "done": .green
        case "failed": .red
        case "cancelled": .orange
        case "running": .blue
        default: .gray
        }

        let label: String = switch status {
        case "done": "完成"
        case "failed": "失败"
        case "cancelled": "已取消"
        case "running": "运行中"
        default: status
        }

        return Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color)
            .cornerRadius(4)
    }
}
