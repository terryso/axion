import Foundation

protocol URLOpening: Sendable {
    func openURL(_ urlString: String) throws
}
