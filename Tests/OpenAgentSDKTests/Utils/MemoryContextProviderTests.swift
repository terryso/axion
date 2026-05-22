import XCTest
@testable import OpenAgentSDK

final class MemoryContextProviderTests: XCTestCase {

    private let provider = MemoryContextProvider()

    private func makeFact(
        kind: MemoryKind = .affordance,
        confidence: Double = 0.8,
        evidenceCount: Int = 2,
        status: MemoryFactStatus = .active
    ) -> MemoryFact {
        MemoryFact(
            id: UUID().uuidString,
            domain: "test",
            content: "\(kind.rawValue) fact conf=\(confidence)",
            status: status,
            confidence: confidence,
            evidenceCount: evidenceCount,
            source: .observation,
            kind: kind,
            createdAt: Date(),
            lastVerifiedAt: Date()
        )
    }

    func testReturnsNilForEmptyFacts() {
        let result = provider.buildContext(domain: "test", facts: [])
        XCTAssertNil(result)
    }

    func testReturnsNilForNoActiveFacts() {
        let candidate = makeFact(status: .candidate)
        let result = provider.buildContext(domain: "test", facts: [candidate])
        XCTAssertNil(result)
    }

    func testGroupsByKind() {
        let facts = [
            makeFact(kind: .affordance),
            makeFact(kind: .avoid),
            makeFact(kind: .observation),
        ]
        let result = provider.buildContext(domain: "test", facts: facts)!
        XCTAssertTrue(result.contains("Recommended Paths"))
        XCTAssertTrue(result.contains("Cautions"))
        XCTAssertTrue(result.contains("Environment Notes"))
    }

    func testCapsAtFivePerKind() {
        var facts: [MemoryFact] = []
        for i in 0..<8 {
            facts.append(makeFact(kind: .affordance, confidence: Double(8 - i) / 10.0))
        }
        let result = provider.buildContext(domain: "test", facts: facts)!

        // Count bullet items in the affordance section
        let affordanceSection = result.components(separatedBy: "### Recommended Paths").last!
            .components(separatedBy: "###").first!
        let bulletCount = affordanceSection.components(separatedBy: "- ").dropFirst().count
        XCTAssertEqual(bulletCount, 5)
    }

    func testSortsByConfidenceDescending() {
        let facts = [
            makeFact(kind: .affordance, confidence: 0.5),
            makeFact(kind: .affordance, confidence: 0.9),
        ]
        let result = provider.buildContext(domain: "test", facts: facts)!

        let range = result.range(of: "conf=0.9")!
        let range2 = result.range(of: "conf=0.5")!
        XCTAssertTrue(range.lowerBound < range2.lowerBound)
    }

    func testIncludesSoftHintsDeclaration() {
        let facts = [makeFact()]
        let result = provider.buildContext(domain: "test", facts: facts)!
        XCTAssertTrue(result.contains("soft hints, not hard rules"))
    }
}
