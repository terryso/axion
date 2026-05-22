// MARK: - Story 21.1 ATDD Tests (GREEN Phase)

import XCTest
@testable import OpenAgentSDK

final class ExperienceTypesTests: XCTestCase {

    // MARK: - ExperienceSource (AC2)

    func testExperienceSourceRawValues() throws {
        XCTAssertEqual(ExperienceSource.conversation.rawValue, "conversation")
        XCTAssertEqual(ExperienceSource.observation.rawValue, "observation")
        XCTAssertEqual(ExperienceSource.imported.rawValue, "imported")
    }

    func testExperienceSourceCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for source: ExperienceSource in [.conversation, .observation, .imported] {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(ExperienceSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }

    // MARK: - ExperienceSignal (AC1)

    func testExperienceSignalCreation() throws {
        let signal = ExperienceSignal.create(
            domain: "testing",
            kind: .affordance,
            content: "Use XCTest for unit tests",
            confidence: 0.8,
            source: .conversation,
            metadata: ["runId": "abc123"]
        )
        XCTAssertEqual(signal.domain, "testing")
        XCTAssertEqual(signal.content, "Use XCTest for unit tests")
        XCTAssertEqual(signal.kind, .affordance)
        XCTAssertEqual(signal.confidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(signal.source, .conversation)
        XCTAssertNotNil(signal.id)
        XCTAssertFalse(signal.id.isEmpty)
        XCTAssertNotNil(signal.metadata)
        XCTAssertEqual(signal.metadata?["runId"], "abc123")
    }

    func testExperienceSignalIdDeterminism() throws {
        let signal1 = ExperienceSignal.create(
            domain: "coding",
            kind: .affordance,
            content: "Use guard let",
            confidence: 0.7,
            source: .conversation
        )
        let signal2 = ExperienceSignal.create(
            domain: "coding",
            kind: .affordance,
            content: "Use guard let",
            confidence: 0.7,
            source: .conversation
        )
        XCTAssertEqual(signal1.id, signal2.id)
    }

    func testExperienceSignalDifferentInputsDifferentId() throws {
        let signal1 = ExperienceSignal.create(
            domain: "coding",
            kind: .affordance,
            content: "Use guard let",
            confidence: 0.5,
            source: .conversation
        )
        let signal2 = ExperienceSignal.create(
            domain: "deployment",
            kind: .affordance,
            content: "Use guard let",
            confidence: 0.5,
            source: .conversation
        )
        let signal3 = ExperienceSignal.create(
            domain: "coding",
            kind: .affordance,
            content: "Use if let",
            confidence: 0.5,
            source: .conversation
        )
        XCTAssertNotEqual(signal1.id, signal2.id)
        XCTAssertNotEqual(signal1.id, signal3.id)
    }

    func testExperienceSignalCodableRoundTrip() throws {
        let signal = ExperienceSignal.create(
            domain: "navigation",
            kind: .avoid,
            content: "Avoid force unwrap",
            confidence: 0.9,
            source: .observation,
            metadata: ["sessionId": "sess-1", "turnIndex": "3"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(signal)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExperienceSignal.self, from: data)

        // Compare individual fields because ISO8601 round-trip loses sub-second Date precision.
        XCTAssertEqual(decoded.id, signal.id)
        XCTAssertEqual(decoded.domain, signal.domain)
        XCTAssertEqual(decoded.content, signal.content)
        XCTAssertEqual(decoded.kind, signal.kind)
        XCTAssertEqual(decoded.confidence, signal.confidence, accuracy: 0.001)
        XCTAssertEqual(decoded.source, signal.source)
        XCTAssertEqual(decoded.metadata?.count, signal.metadata?.count)
        XCTAssertEqual(decoded.metadata?["sessionId"], signal.metadata?["sessionId"])
        XCTAssertEqual(decoded.metadata?["turnIndex"], signal.metadata?["turnIndex"])
        // Date should be within 1 second after ISO8601 round-trip
        XCTAssertEqual(decoded.createdAt.timeIntervalSince(signal.createdAt), 0, accuracy: 1.0)
    }

    func testExperienceSignalMetadataNil() throws {
        let signal = ExperienceSignal.create(
            domain: "test",
            kind: .observation,
            content: "Some observation",
            confidence: 0.5,
            source: .conversation,
            metadata: nil
        )
        XCTAssertNil(signal.metadata)
    }

    func testExperienceSignalMetadataPresent() throws {
        let metadata: [String: String] = [
            "runId": "run-42",
            "sessionId": "sess-7",
            "turnIndex": "5",
        ]
        let signal = ExperienceSignal.create(
            domain: "test",
            kind: .affordance,
            content: "Metadata test",
            confidence: 0.6,
            source: .conversation,
            metadata: metadata
        )
        XCTAssertEqual(signal.metadata?.count, 3)
        XCTAssertEqual(signal.metadata?["runId"], "run-42")
        XCTAssertEqual(signal.metadata?["sessionId"], "sess-7")
        XCTAssertEqual(signal.metadata?["turnIndex"], "5")
    }

    // MARK: - ExperienceSignal Confidence Clamping (AC1 edge cases)

    func testExperienceSignalConfidenceClampingNegative() throws {
        let signal = ExperienceSignal.create(
            domain: "test",
            kind: .affordance,
            content: "Negative confidence",
            confidence: -0.5,
            source: .conversation
        )
        XCTAssertEqual(signal.confidence, 0.0, accuracy: 0.001)
    }

    func testExperienceSignalConfidenceClampingAboveOne() throws {
        let signal = ExperienceSignal.create(
            domain: "test",
            kind: .affordance,
            content: "Over-confidence",
            confidence: 2.5,
            source: .conversation
        )
        XCTAssertEqual(signal.confidence, 1.0, accuracy: 0.001)
    }

    func testExperienceSignalConfidenceZero() throws {
        let signal = ExperienceSignal.create(
            domain: "test",
            kind: .affordance,
            content: "Zero confidence",
            confidence: 0.0,
            source: .conversation
        )
        XCTAssertEqual(signal.confidence, 0.0, accuracy: 0.001)
    }

    func testExperienceSignalConfidenceClampedViaCodable() throws {
        var json = """
        {"id":"abc","domain":"test","content":"c","kind":"affordance","confidence":-0.5,"source":"conversation","createdAt":0,"metadata":null}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let signal = try decoder.decode(ExperienceSignal.self, from: data)
        XCTAssertEqual(signal.confidence, 0.0, accuracy: 0.001)
    }

    func testExperienceSignalConfidenceClampedViaCodableAboveOne() throws {
        let json = """
        {"id":"abc","domain":"test","content":"c","kind":"affordance","confidence":3.0,"source":"conversation","createdAt":0,"metadata":null}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let signal = try decoder.decode(ExperienceSignal.self, from: data)
        XCTAssertEqual(signal.confidence, 1.0, accuracy: 0.001)
    }

    // MARK: - ExperienceSignal.toFact() (AC6)

    func testToFactConversionConversationSource() throws {
        let signal = ExperienceSignal.create(
            domain: "testing",
            kind: .affordance,
            content: "Use mock objects",
            confidence: 0.8,
            source: .conversation
        )
        let fact = signal.toFact()
        XCTAssertEqual(fact.source, .observation)
    }

    func testToFactConversionObservationSource() throws {
        let signal = ExperienceSignal.create(
            domain: "infra",
            kind: .observation,
            content: "Server runs on port 8080",
            confidence: 0.9,
            source: .observation
        )
        let fact = signal.toFact()
        XCTAssertEqual(fact.source, .observation)
    }

    func testToFactConversionImportedSource() throws {
        let signal = ExperienceSignal.create(
            domain: "onboarding",
            kind: .affordance,
            content: "Prefer SPM",
            confidence: 0.7,
            source: .imported
        )
        let fact = signal.toFact()
        XCTAssertEqual(fact.source, .imported)
    }

    func testToFactMapsFields() throws {
        let signal = ExperienceSignal.create(
            domain: "coding",
            kind: .avoid,
            content: "Avoid force unwrap",
            confidence: 0.85,
            source: .conversation
        )
        let fact = signal.toFact()
        XCTAssertEqual(fact.status, .candidate)
        XCTAssertEqual(fact.evidenceCount, 1)
        XCTAssertEqual(fact.confidence, 0.85, accuracy: 0.001)
        XCTAssertEqual(fact.domain, "coding")
        XCTAssertEqual(fact.content, "Avoid force unwrap")
        XCTAssertEqual(fact.kind, .avoid)
    }

    // MARK: - ExtractionConfig (AC4)

    func testExtractionConfigDefaults() throws {
        let config = ExtractionConfig()
        XCTAssertFalse(config.antiPatternKeywords.isEmpty)
        XCTAssertEqual(config.minSignalConfidence, 0.4, accuracy: 0.001)
        XCTAssertEqual(config.maxSignalsPerExtraction, 10)
        XCTAssertNil(config.domain)
    }

    func testExtractionConfigCustomInit() throws {
        let customKeywords = ["custom pattern"]
        let config = ExtractionConfig(
            antiPatternKeywords: customKeywords,
            minSignalConfidence: 0.8,
            maxSignalsPerExtraction: 5,
            domain: "testing"
        )
        XCTAssertEqual(config.antiPatternKeywords, customKeywords)
        XCTAssertEqual(config.minSignalConfidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(config.maxSignalsPerExtraction, 5)
        XCTAssertEqual(config.domain, "testing")
    }

    func testExtractionConfigCodableRoundTrip() throws {
        let config = ExtractionConfig(
            antiPatternKeywords: ["timeout"],
            minSignalConfidence: 0.6,
            maxSignalsPerExtraction: 20,
            domain: "infra"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExtractionConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testExtractionConfigEquatable() throws {
        let config1 = ExtractionConfig()
        let config2 = ExtractionConfig()
        XCTAssertEqual(config1, config2)

        let config3 = ExtractionConfig(minSignalConfidence: 0.9)
        XCTAssertNotEqual(config1, config3)
    }

    // MARK: - ExtractionConfig Anti-Pattern Defaults (AC7)

    func testDefaultAntiPatternKeywordsContainsEnvironmentFailures() throws {
        let config = ExtractionConfig()
        let keywords = config.antiPatternKeywords
        XCTAssertTrue(keywords.contains("command not found"),
                       "Should contain 'command not found'")
        XCTAssertTrue(keywords.contains("not installed"),
                       "Should contain 'not installed'")
    }

    func testDefaultAntiPatternKeywordsContainsTransientErrors() throws {
        let config = ExtractionConfig()
        let keywords = config.antiPatternKeywords
        XCTAssertTrue(keywords.contains("timeout"),
                       "Should contain 'timeout'")
        XCTAssertTrue(keywords.contains("temporary failure"),
                       "Should contain 'temporary failure'")
    }

    func testDefaultAntiPatternKeywordsContainsOneOffTaskNarratives() throws {
        let config = ExtractionConfig()
        let keywords = config.antiPatternKeywords
        XCTAssertTrue(keywords.contains("summarize today's"),
                       "Should contain 'summarize today''s'")
    }

    // MARK: - ExtractionResult (AC5)

    func testExtractionResultConstruction() throws {
        let signals = [
            ExperienceSignal.create(
                domain: "test",
                kind: .affordance,
                content: "Signal 1",
                confidence: 0.7,
                source: .conversation
            ),
        ]
        let now = Date()
        let result = ExtractionResult(
            signals: signals,
            skippedCount: 3,
            extractionDate: now,
            sourceMessageCount: 10
        )
        XCTAssertEqual(result.signals.count, 1)
        XCTAssertEqual(result.skippedCount, 3)
        XCTAssertEqual(result.sourceMessageCount, 10)
        XCTAssertEqual(result.extractionDate, now)
    }

    func testExtractionResultEquatable() throws {
        let signals = [
            ExperienceSignal.create(
                domain: "test",
                kind: .affordance,
                content: "Signal",
                confidence: 0.5,
                source: .observation
            ),
        ]
        let now = Date()
        let result1 = ExtractionResult(signals: signals, skippedCount: 2, extractionDate: now, sourceMessageCount: 5)
        let result2 = ExtractionResult(signals: signals, skippedCount: 2, extractionDate: now, sourceMessageCount: 5)
        XCTAssertEqual(result1, result2)
    }

    // MARK: - ExperienceExtractor Protocol (AC3)

    func testExperienceExtractorProtocolConformance() async throws {
        let mock = MockExperienceExtractor()
        let config = ExtractionConfig()
        let messages: [SDKMessage] = [
            .assistant(.init(text: "Test message", model: "test", stopReason: "end_turn")),
        ]
        let result = try await mock.extract(from: messages, config: config)
        XCTAssertEqual(result.signals.count, 1)
        XCTAssertEqual(result.signals.first?.domain, "test-domain")
        XCTAssertEqual(result.sourceMessageCount, 1)
    }

    func testExperienceExtractorProtocolIsSendable() throws {
        func acceptSendable<T: ExperienceExtractor>(_ extractor: T) {
            _ = extractor
        }
        acceptSendable(MockExperienceExtractor())
    }
}

// MARK: - Mock ExperienceExtractor (proves protocol is implementable)

private struct MockExperienceExtractor: ExperienceExtractor {
    func extract(from messages: [SDKMessage], config: ExtractionConfig) async throws -> ExtractionResult {
        let signal = ExperienceSignal.create(
            domain: "test-domain",
            kind: .affordance,
            content: "Test signal from mock",
            confidence: 0.5,
            source: .conversation
        )
        return ExtractionResult(
            signals: [signal],
            skippedCount: 0,
            extractionDate: Date(),
            sourceMessageCount: messages.count
        )
    }
}
