import AppKit
import Foundation

/// Errors thrown by `URLOpenerService`.
enum URLOpenerError: Error, LocalizedError {
    case invalidURL(String)
    case unsupportedScheme(String)
    case failedToOpen(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let urlString):
            return "Invalid URL: '\(urlString)'"
        case .unsupportedScheme(let urlString):
            return "Unsupported URL scheme: '\(urlString)'. Only http and https are allowed."
        case .failedToOpen(let urlString):
            return "Failed to open URL: '\(urlString)'"
        }
    }

    var errorCode: String {
        switch self {
        case .invalidURL:
            return "invalid_url"
        case .unsupportedScheme:
            return "unsupported_scheme"
        case .failedToOpen:
            return "failed_to_open"
        }
    }

    var suggestion: String {
        switch self {
        case .invalidURL:
            return "Provide a valid http:// or https:// URL."
        case .unsupportedScheme:
            return "Only http:// and https:// URLs are supported."
        case .failedToOpen:
            return "Ensure the URL is accessible and a default browser is configured."
        }
    }
}

/// Service that opens URLs in the default browser using NSWorkspace.
struct URLOpenerService: URLOpening {

    func openURL(_ urlString: String) throws {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            if let url = URL(string: urlString), url.scheme != nil {
                throw URLOpenerError.unsupportedScheme(urlString)
            }
            throw URLOpenerError.invalidURL(urlString)
        }
        guard NSWorkspace.shared.open(url) else {
            throw URLOpenerError.failedToOpen(urlString)
        }
    }
}
