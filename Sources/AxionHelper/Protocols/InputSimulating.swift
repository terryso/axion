import CoreGraphics
import Foundation

protocol InputSimulating: Sendable {
    func click(x: Int, y: Int) throws
    func doubleClick(x: Int, y: Int) throws
    func rightClick(x: Int, y: Int) throws
    func scroll(direction: String, amount: Int) throws
    func drag(fromX: Int, fromY: Int, toX: Int, toY: Int) throws
    func typeText(_ text: String) throws
    func pressKey(_ key: String) throws
    func hotkey(_ keys: String) throws
}
