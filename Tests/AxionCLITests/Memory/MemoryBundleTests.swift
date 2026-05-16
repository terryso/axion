import Foundation
import Testing

@testable import AxionCLI

// Story 12.3 AC1: MemoryBundle and ExportedDomain Codable round-trip

@Suite("MemoryBundle + ExportedDomain")
struct MemoryBundleTests {

    @Test("MemoryBundle Codable round-trip preserves all fields")
    func bundleRoundTrip() throws {
        let date = Date()
        let facts: [AppMemoryFact] = [
            AppMemoryFact.create(domain: "com.apple.finder", kind: .affordance, description: "test fact"),
        ]
        let domain = ExportedDomain(domain: "com.apple.finder", facts: facts)
        let bundle = MemoryBundle(schemaVersion: 1, exportedAt: date, memories: [domain])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MemoryBundle.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.memories.count == 1)
        #expect(decoded.memories[0].domain == "com.apple.finder")
        #expect(decoded.memories[0].facts.count == 1)
        #expect(decoded.memories[0].facts[0].description == "test fact")
    }

    @Test("MemoryBundle JSON uses snake_case keys")
    func snakeCaseKeys() throws {
        let bundle = MemoryBundle(memories: [])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"schema_version\""))
        #expect(json.contains("\"exported_at\""))
        #expect(json.contains("\"memories\""))
    }

    @Test("ExportedDomain round-trip with multiple facts")
    func exportedDomainRoundTrip() throws {
        let facts = [
            AppMemoryFact.create(domain: "test", kind: .affordance, description: "fact A"),
            AppMemoryFact.create(domain: "test", kind: .avoid, description: "fact B"),
            AppMemoryFact.create(domain: "test", kind: .observation, description: "fact C"),
        ]
        let domain = ExportedDomain(domain: "test", facts: facts)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(domain)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportedDomain.self, from: data)

        #expect(decoded.domain == "test")
        #expect(decoded.facts.count == 3)
        #expect(decoded.facts[0].kind == .affordance)
        #expect(decoded.facts[1].kind == .avoid)
        #expect(decoded.facts[2].kind == .observation)
    }
}
