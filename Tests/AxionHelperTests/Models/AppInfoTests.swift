import XCTest
@testable import AxionHelper

final class AppInfoTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let original = AppInfo(pid: 1234, appName: "Calculator", bundleId: "com.apple.calculator")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppInfo.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTrip_nilBundleId() throws {
        let original = AppInfo(pid: 5678, appName: "SomeApp", bundleId: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppInfo.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testJSONKeys() throws {
        let info = AppInfo(pid: 99, appName: "Finder", bundleId: "com.apple.finder")
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["pid"])
        XCTAssertNotNil(json?["app_name"])
        XCTAssertNotNil(json?["bundle_id"])
    }
}
