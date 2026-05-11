import Foundation

public enum ToolNames {
    public static let launchApp = "launch_app"
    public static let listApps = "list_apps"
    public static let quitApp = "quit_app"
    public static let activateWindow = "activate_window"
    public static let listWindows = "list_windows"
    public static let getWindowState = "get_window_state"
    public static let moveWindow = "move_window"
    public static let resizeWindow = "resize_window"
    public static let click = "click"
    public static let doubleClick = "double_click"
    public static let rightClick = "right_click"
    public static let typeText = "type_text"
    public static let pressKey = "press_key"
    public static let hotkey = "hotkey"
    public static let scroll = "scroll"
    public static let drag = "drag"
    public static let screenshot = "screenshot"
    public static let getAccessibilityTree = "get_accessibility_tree"
    public static let openUrl = "open_url"
    public static let getFileInfo = "get_file_info"
    public static let validateWindow = "validate_window"

    /// All available tool names for prompt building.
    public static let allToolNames: [String] = [
        launchApp, listApps, quitApp, activateWindow, listWindows,
        getWindowState, moveWindow, resizeWindow, click, doubleClick,
        rightClick, typeText, pressKey, hotkey, scroll, drag,
        screenshot, getAccessibilityTree, openUrl, getFileInfo,
        validateWindow
    ]

    /// Tools that require foreground interaction and are blocked in shared seat mode.
    public static let foregroundToolNames: Set<String> = [
        click, doubleClick, rightClick,
        typeText, pressKey, hotkey,
        scroll, drag
    ]
}
