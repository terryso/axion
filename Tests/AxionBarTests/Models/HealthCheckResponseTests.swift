import Testing
import Foundation
@testable import AxionBar

@Suite("HealthCheckResponse")
struct HealthCheckResponseTests {

    @Test("decodes valid JSON")
    func decodesValidJSON() throws {
        let json = """
        {"status": "ok", "version": "1.2.3"}
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HealthCheckResponse.self, from: data)
        #expect(response.status == "ok")
        #expect(response.version == "1.2.3")
    }

    @Test("decodes with different status values")
    func decodesDifferentStatus() throws {
        let json = """
        {"status": "degraded", "version": "0.0.1-dev"}
        """
        let data = Data(json.utf8)
        let response = try JSONDecoder().decode(HealthCheckResponse.self, from: data)
        #expect(response.status == "degraded")
        #expect(response.version == "0.0.1-dev")
    }

    @Test("fails to decode missing version")
    func failsMissingVersion() {
        let json = """
        {"status": "ok"}
        """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HealthCheckResponse.self, from: data)
        }
    }

    @Test("fails to decode missing status")
    func failsMissingStatus() {
        let json = """
        {"version": "1.0.0"}
        """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HealthCheckResponse.self, from: data)
        }
    }

    @Test("equatable conformance")
    func equatable() {
        let a = HealthCheckResponse(status: "ok", version: "1.0")
        let b = HealthCheckResponse(status: "ok", version: "1.0")
        let c = HealthCheckResponse(status: "ok", version: "2.0")
        #expect(a == b)
        #expect(a != c)
    }
}
