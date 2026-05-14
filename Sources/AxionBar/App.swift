import SwiftUI
import UserNotifications

// MARK: - AppDelegate (LSUIElement = no Dock icon)

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct AxionBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = StatusBarController()

    var body: some Scene {
        MenuBarExtra {
            AxionBarMenuContent(controller: controller)
        } label: {
            Image(systemName: controller.statusIcon)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct AxionBarMenuContent: View {
    @ObservedObject var controller: StatusBarController

    var body: some View {
        Button("快速执行...") {
            controller.quickRunWindow.show(controller: controller)
        }
        .disabled(controller.connectionState == .disconnected)

        Menu("技能列表") {
            if controller.connectionState == .disconnected {
                Text("（未连接）")
            } else if controller.availableSkills.isEmpty {
                Text("（暂无技能）")
            } else {
                ForEach(controller.availableSkills, id: \.name) { skill in
                    Button("\(skill.name) (\(skill.stepCount)步)") {
                        Task { await controller.runSkill(name: skill.name) }
                    }
                }
            }
        }
        .disabled(controller.connectionState == .disconnected)

        if controller.connectionState == .running, let task = controller.currentTask {
            Divider()

            Button("运行中: \(task) \(controller.stepProgressText ?? "")") {
                if let runId = controller.currentRunId {
                    controller.taskDetailPanel.show(runId: runId, task: task, controller: controller)
                }
            }
        }

        Divider()

        Button("任务历史...") {
            controller.runHistoryWindow.show(controller: controller)
        }
        .disabled(controller.connectionState == .disconnected)

        Divider()

        if controller.connectionState == .disconnected {
            if controller.isServerManagedByUs {
                Button("重启服务") {
                    controller.startServer()
                }
            } else {
                Button("启动服务") {
                    controller.startServer()
                }
            }
        } else {
            Button("重启服务") {
                controller.stopServer()
                controller.startServer()
            }
        }

        Divider()

        Button("设置...") {
            controller.settingsWindow.show(controller: controller)
        }

        if let version = controller.serverVersion {
            Text("Axion v\(version)")
        }

        Divider()

        Button("退出 AxionBar") {
            NSApplication.shared.terminate(nil)
        }
    }
}
