import Foundation

/// An accessibility element node in the AX tree.
struct AXElement: Codable, Equatable {
    let role: String
    let title: String?
    let value: String?
    let identifier: String?
    let bounds: WindowBounds?
    let children: [AXElement]

    init(role: String, title: String? = nil, value: String? = nil, identifier: String? = nil, bounds: WindowBounds? = nil, children: [AXElement] = []) {
        self.role = role
        self.title = title
        self.value = value
        self.identifier = identifier
        self.bounds = bounds
        self.children = children
    }
}
