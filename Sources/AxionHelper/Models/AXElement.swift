import Foundation

/// An accessibility element node in the AX tree.
struct AXElement: Codable, Equatable {
    let role: String
    let title: String?
    let value: String?
    let bounds: WindowBounds?
    let children: [AXElement]
}
