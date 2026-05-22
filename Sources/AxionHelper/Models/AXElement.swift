import Foundation

/// Pre-computed center point of an AX element.
struct ElementCenter: Codable, Equatable {
    let x: Int
    let y: Int
}

/// An accessibility element node in the AX tree.
struct AXElement: Codable, Equatable {
    let role: String
    let title: String?
    let value: String?
    let identifier: String?
    let bounds: WindowBounds?
    let center: ElementCenter?
    let children: [AXElement]

    init(role: String, title: String? = nil, value: String? = nil, identifier: String? = nil, bounds: WindowBounds? = nil, center: ElementCenter? = nil, children: [AXElement] = []) {
        self.role = role
        self.title = title
        self.value = value
        self.identifier = identifier
        self.bounds = bounds
        self.center = center
        self.children = children
    }
}
