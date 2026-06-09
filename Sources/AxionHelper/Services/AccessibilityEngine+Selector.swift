import Foundation

extension AccessibilityEngineService {

    // MARK: - Selector Types

    struct SelectorMatchResult: Codable {
        let x: Int
        let y: Int
        let role: String
        let title: String?
    }

    enum SelectorError: Error, LocalizedError, ToolErrorProtocol {
        case noMatch(query: SelectorQuery)
        case ordinalOutOfRange(ordinal: Int, matchCount: Int)

        var errorDescription: String? {
            switch self {
            case .noMatch(let query):
                return "No AX element matches selector: role=\(query.role ?? "*"), title=\(query.title ?? "*"), title_contains=\(query.titleContains ?? "*"), ax_id=\(query.axId ?? "*")"
            case .ordinalOutOfRange(let ordinal, let count):
                return "Ordinal \(ordinal) out of range (found \(count) matching elements)"
            }
        }

        var errorCode: String {
            switch self {
            case .noMatch: return "selector_no_match"
            case .ordinalOutOfRange: return "selector_ordinal_out_of_range"
            }
        }

        var suggestion: String {
            switch self {
            case .noMatch:
                return "Use get_accessibility_tree to inspect the current AX tree and find the correct selector values."
            case .ordinalOutOfRange:
                return "Use a lower ordinal value or inspect the AX tree to count matching elements."
            }
        }
    }

    // MARK: - Selector Resolution

    func resolveSelector(windowId: Int, query: SelectorQuery) throws -> SelectorMatchResult {
        let ordinal = query.ordinal ?? 0
        guard ordinal >= 0 else {
            throw SelectorError.ordinalOutOfRange(ordinal: ordinal, matchCount: 0)
        }

        let tree = try getAXTree(windowId: windowId, maxNodes: 500)
        let matches = collectMatches(element: tree, query: query)

        guard !matches.isEmpty else {
            throw SelectorError.noMatch(query: query)
        }

        guard ordinal < matches.count else {
            throw SelectorError.ordinalOutOfRange(ordinal: ordinal, matchCount: matches.count)
        }

        let match = matches[ordinal]
        return match
    }

    func collectMatches(element: AXElement, query: SelectorQuery) -> [SelectorMatchResult] {
        var results: [SelectorMatchResult] = []

        if matchesQuery(element: element, query: query),
           let bounds = element.bounds, bounds.width > 0, bounds.height > 0 {
            let centerX = bounds.x + bounds.width / 2
            let centerY = bounds.y + bounds.height / 2
            results.append(SelectorMatchResult(
                x: centerX,
                y: centerY,
                role: element.role,
                title: element.title
            ))
        }

        for child in element.children {
            results.append(contentsOf: collectMatches(element: child, query: query))
        }

        return results
    }

    private func matchesQuery(element: AXElement, query: SelectorQuery) -> Bool {
        guard query.title != nil || query.titleContains != nil || query.axId != nil || query.role != nil else {
            return false
        }
        if let role = query.role, element.role != role { return false }
        if let title = query.title, element.title != title { return false }
        if let titleContains = query.titleContains {
            guard let elementTitle = element.title,
                  elementTitle.localizedCaseInsensitiveContains(titleContains) else { return false }
        }
        if let axId = query.axId, element.identifier != axId { return false }
        return true
    }
}
