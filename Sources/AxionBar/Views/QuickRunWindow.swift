import SwiftUI
import AppKit

@MainActor
final class QuickRunWindow {
    private var panel: NSPanel?

    func show(controller: StatusBarController) {
        if let panel, panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = QuickRunInputView(controller: controller) { [weak self] in
            self?.panel?.close()
        }

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.title = "快速执行"
        newPanel.contentView = NSHostingView(rootView: contentView)
        newPanel.center()
        newPanel.makeKeyAndOrderFront(nil)

        self.panel = newPanel
    }
}

struct QuickRunInputView: View {
    @ObservedObject var controller: StatusBarController
    @State private var taskText = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $taskText)
                .font(.body)
                .frame(minHeight: 50, maxHeight: 80)
                .border(Color.gray.opacity(0.3))
                .padding(.horizontal)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            HStack {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                if controller.connectionState == .disconnected {
                    Text("请先启动服务")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                Spacer()

                Button("取消") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("执行") {
                    submitTask()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting || controller.connectionState == .disconnected)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
    }

    private func submitTask() {
        let trimmed = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                let response = try await controller.submitTask(task: trimmed)
                controller.currentRunId = response.runId
                controller.currentTask = trimmed
                controller.connectionState = .running
                controller.startRunMonitoring(runId: response.runId)
                onDismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
