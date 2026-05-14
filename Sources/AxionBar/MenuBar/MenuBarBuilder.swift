import AppKit

@MainActor
final class MenuBarBuilder {
    private let controller: StatusBarController

    init(controller: StatusBarController) {
        self.controller = controller
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 快速执行 (disabled placeholder)
        let quickRun = NSMenuItem(
            title: "快速执行...",
            action: nil,
            keyEquivalent: ""
        )
        quickRun.isEnabled = false
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

        // 任务历史 (disabled placeholder)
        let taskHistory = NSMenuItem(
            title: "任务历史...",
            action: nil,
            keyEquivalent: ""
        )
        taskHistory.isEnabled = false
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
