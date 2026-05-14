import AppKit

@MainActor
final class MenuBarBuilder {
    private let controller: StatusBarController

    init(controller: StatusBarController) {
        self.controller = controller
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 快速执行
        let quickRun = NSMenuItem(
            title: "快速执行...",
            action: #selector(showQuickRun),
            keyEquivalent: ""
        )
        quickRun.target = self
        quickRun.isEnabled = controller.connectionState != .disconnected
        menu.addItem(quickRun)

        // 技能列表 (disabled placeholder)
        let skillList = NSMenuItem(
            title: "技能列表",
            action: nil,
            keyEquivalent: ""
        )
        skillList.isEnabled = false
        let skillSubMenu = NSMenu()
        skillSubMenu.addItem(NSMenuItem(title: "（即将支持）", action: nil, keyEquivalent: ""))
        skillList.submenu = skillSubMenu
        menu.addItem(skillList)

        // Running task section
        if controller.connectionState == .running, let task = controller.currentTask {
            menu.addItem(NSMenuItem.separator())

            let progress = controller.stepProgressText ?? ""
            let runningItem = NSMenuItem(
                title: "运行中: \(task) \(progress)",
                action: #selector(showTaskDetail),
                keyEquivalent: ""
            )
            runningItem.target = self
            menu.addItem(runningItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 任务历史
        let taskHistory = NSMenuItem(
            title: "任务历史...",
            action: #selector(showTaskHistory),
            keyEquivalent: ""
        )
        taskHistory.target = self
        taskHistory.isEnabled = controller.connectionState != .disconnected
        menu.addItem(taskHistory)

        menu.addItem(NSMenuItem.separator())

        // 启动服务 / 重启服务
        if controller.connectionState == .disconnected {
            if controller.isServerManagedByUs {
                let restartItem = NSMenuItem(
                    title: "重启服务",
                    action: #selector(startServer),
                    keyEquivalent: ""
                )
                restartItem.target = self
                menu.addItem(restartItem)
            } else {
                let startItem = NSMenuItem(
                    title: "启动服务",
                    action: #selector(startServer),
                    keyEquivalent: ""
                )
                startItem.target = self
                menu.addItem(startItem)
            }
        } else {
            let restartItem = NSMenuItem(
                title: "重启服务",
                action: #selector(restartServer),
                keyEquivalent: ""
            )
            restartItem.target = self
            menu.addItem(restartItem)
        }

        menu.addItem(NSMenuItem.separator())

        // 设置
        let settingsItem = NSMenuItem(
            title: "设置...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 版本号（如果已连接）
        if let version = controller.serverVersion {
            let versionItem = NSMenuItem(
                title: "Axion v\(version)",
                action: nil,
                keyEquivalent: ""
            )
            versionItem.isEnabled = false
            menu.addItem(versionItem)
        }

        // 退出
        let quitItem = NSMenuItem(
            title: "退出 AxionBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    @objc private func showQuickRun() {
        controller.quickRunWindow.show(controller: controller)
    }

    @objc private func showTaskDetail() {
        guard let runId = controller.currentRunId, let task = controller.currentTask else { return }
        controller.taskDetailPanel.show(runId: runId, task: task, controller: controller)
    }

    @objc private func showTaskHistory() {
        controller.runHistoryWindow.show(controller: controller)
    }

    @objc private func startServer() {
        controller.startServer()
    }

    @objc private func restartServer() {
        controller.stopServer()
        controller.startServer()
    }

    @objc private func openSettings() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".axion")
        let configFile = configDir.appendingPathComponent("config.json")
        NSWorkspace.shared.open(configFile)
    }
}
