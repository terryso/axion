import XCTest
@testable import OpenAgentSDK

final class ReviewScheduleConfigTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultValues() {
        let config = ReviewScheduleConfig()
        XCTAssertEqual(config.memoryReviewInterval, 4)
        XCTAssertEqual(config.skillReviewInterval, 6)
        XCTAssertEqual(config.minMessagesForReview, 4)
        XCTAssertNil(config.reviewModel)
    }

    // MARK: - Custom Values

    func testCustomValues() {
        let config = ReviewScheduleConfig(
            memoryReviewInterval: 2,
            skillReviewInterval: 3,
            minMessagesForReview: 5,
            reviewModel: "claude-haiku-4-5-20251001"
        )
        XCTAssertEqual(config.memoryReviewInterval, 2)
        XCTAssertEqual(config.skillReviewInterval, 3)
        XCTAssertEqual(config.minMessagesForReview, 5)
        XCTAssertEqual(config.reviewModel, "claude-haiku-4-5-20251001")
    }

    // MARK: - Equatable

    func testEquatable() {
        let a = ReviewScheduleConfig()
        let b = ReviewScheduleConfig()
        XCTAssertEqual(a, b)

        let c = ReviewScheduleConfig(memoryReviewInterval: 8)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let config = ReviewScheduleConfig(
            memoryReviewInterval: 3,
            skillReviewInterval: 5,
            minMessagesForReview: 2,
            reviewModel: "claude-sonnet-4-6"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ReviewScheduleConfig.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testCodableNilReviewModel() throws {
        let config = ReviewScheduleConfig()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ReviewScheduleConfig.self, from: data)
        XCTAssertNil(decoded.reviewModel)
    }

    // Note: precondition validation for intervals<=0 and minMessagesForReview<=0
    // is enforced at runtime via precondition() and cannot be tested in-process
    // without crashing XCTest. The following invalid constructions trigger
    // preconditionFailure:
    //   ReviewScheduleConfig(memoryReviewInterval: 0)
    //   ReviewScheduleConfig(memoryReviewInterval: -1)
    //   ReviewScheduleConfig(skillReviewInterval: 0)
    //   ReviewScheduleConfig(minMessagesForReview: 0)
    //   ReviewScheduleConfig(minMessagesForReview: -1)
    // didSet mutations also trigger preconditionFailure:
    //   var c = ReviewScheduleConfig(); c.memoryReviewInterval = 0
    //   var c = ReviewScheduleConfig(); c.skillReviewInterval = 0
    //   var c = ReviewScheduleConfig(); c.minMessagesForReview = 0
}
