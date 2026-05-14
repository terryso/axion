import SwiftUI

// MARK: - AppDelegate (LSUIElement = no Dock icon)

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
        Button("快速执行...") {}
            .disabled(true)

        Menu("技能列表") {
            Text("（即将支持）")
        }
        .disabled(true)

        Button("任务历史...") {}
            .disabled(true)

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
            let configDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".axion")
            let configFile = configDir.appendingPathComponent("config.json")
            NSWorkspace.shared.open(configFile)
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
