import Testing
import AppKit
@testable import AxionBar

@MainActor
@Suite("MenuBarBuilder")
struct MenuBarBuilderTests {

    @Test("buildMenu returns non-empty menu when disconnected")
    func buildMenuDisconnected() {
        let controller = StatusBarController()
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        #expect(menu.items.count > 0)
    }

    @Test("menu contains 启动服务 when disconnected")
    func menuContainsStartServer() {
        let controller = StatusBarController()
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let titles = menu.items.compactMap { $0.title }
        #expect(titles.contains("启动服务"))
    }

    @Test("menu contains 退出 AxionBar")
    func menuContainsQuit() {
        let controller = StatusBarController()
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let titles = menu.items.compactMap { $0.title }
        #expect(titles.contains("退出 AxionBar"))
    }

    @Test("menu contains 设置")
    func menuContainsSettings() {
        let controller = StatusBarController()
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let titles = menu.items.compactMap { $0.title }
        #expect(titles.contains("设置..."))
    }

    @Test("placeholder items are disabled")
    func placeholderItemsDisabled() {
        let controller = StatusBarController()
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()

        let disabledTitles = menu.items.filter { !$0.isEnabled }.compactMap { $0.title }
        #expect(disabledTitles.contains("快速执行..."))
        #expect(disabledTitles.contains("任务历史..."))
    }

    @Test("menu has separators")
    func menuHasSeparators() {
        let controller = StatusBarController()
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let separators = menu.items.filter { $0.isSeparatorItem }
        #expect(separators.count >= 2)
    }

    @Test("menu contains 重启服务 when connected")
    func menuContainsRestartServer() {
        let controller = StatusBarController()
        controller.connectionState = .connected
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let titles = menu.items.compactMap { $0.title }
        #expect(titles.contains("重启服务"))
        #expect(!titles.contains("启动服务"))
    }

    @Test("menu contains 重启服务 when running")
    func menuContainsRestartServerWhenRunning() {
        let controller = StatusBarController()
        controller.connectionState = .running
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let titles = menu.items.compactMap { $0.title }
        #expect(titles.contains("重启服务"))
    }

    @Test("AC5: menu shows 启动服务 when disconnected and not managed by us")
    func menuShowsStartWhenNotManaged() {
        let controller = StatusBarController()
        // Default: disconnected, isServerManagedByUs = false
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let titles = menu.items.compactMap { $0.title }
        #expect(titles.contains("启动服务"))
    }

    @Test("menu shows version when serverVersion is set")
    func menuShowsVersion() {
        let controller = StatusBarController()
        controller.connectionState = .connected
        controller.serverVersion = "3.1.0"
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let titles = menu.items.compactMap { $0.title }
        #expect(titles.contains("Axion v3.1.0"))
    }

    @Test("menu hides version when serverVersion is nil")
    func menuHidesVersion() {
        let controller = StatusBarController()
        controller.connectionState = .connected
        // serverVersion is nil by default
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let titles = menu.items.compactMap { $0.title }
        let versionTitles = titles.filter { $0.hasPrefix("Axion v") }
        #expect(versionTitles.isEmpty)
    }

    @Test("技能列表 has submenu with disconnected placeholder")
    func skillListSubmenu() {
        let controller = StatusBarController()
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let skillItem = menu.items.first { $0.title == "技能列表" }
        #expect(skillItem != nil)
        #expect(skillItem?.submenu != nil)
        let subTitles = skillItem?.submenu?.items.compactMap { $0.title } ?? []
        #expect(subTitles.contains("（未连接）"))
    }

    @Test("设置 item has keyboard shortcut comma")
    func settingsKeyboardShortcut() {
        let controller = StatusBarController()
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let settingsItem = menu.items.first { $0.title == "设置..." }
        #expect(settingsItem != nil)
        #expect(settingsItem?.keyEquivalent == ",")
    }

    @Test("退出 item has keyboard shortcut q")
    func quitKeyboardShortcut() {
        let controller = StatusBarController()
        let builder = MenuBarBuilder(controller: controller)
        let menu = builder.buildMenu()
        let quitItem = menu.items.first { $0.title == "退出 AxionBar" }
        #expect(quitItem != nil)
        #expect(quitItem?.keyEquivalent == "q")
    }
}
