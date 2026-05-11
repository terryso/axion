import Foundation

protocol WindowManaging: Sendable {
    func listWindows(pid: Int32?) -> [WindowInfo]
    func getWindowState(windowId: Int) throws -> WindowState
    func getAXTree(windowId: Int, maxNodes: Int) throws -> AXElement
    func activateWindow(pid: Int32, windowId: Int?) throws
}
