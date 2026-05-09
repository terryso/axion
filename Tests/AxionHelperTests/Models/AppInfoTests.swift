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

    // MARK: - Equality

    func testEquality_same() {
        let a = AppInfo(pid: 123, appName: "Test", bundleId: "com.test")
        let b = AppInfo(pid: 123, appName: "Test", bundleId: "com.test")
        XCTAssertEqual(a, b)
    }

    func testEquality_differentPid() {
        let a = AppInfo(pid: 123, appName: "Test", bundleId: nil)
        let b = AppInfo(pid: 456, appName: "Test", bundleId: nil)
        XCTAssertNotEqual(a, b)
    }

    func testEquality_differentName() {
        let a = AppInfo(pid: 123, appName: "Test1", bundleId: nil)
        let b = AppInfo(pid: 123, appName: "Test2", bundleId: nil)
        XCTAssertNotEqual(a, b)
    }

    func testEquality_differentBundleId() {
        let a = AppInfo(pid: 123, appName: "Test", bundleId: "com.a")
        let b = AppInfo(pid: 123, appName: "Test", bundleId: "com.b")
        XCTAssertNotEqual(a, b)
    }

    func testEquality_nilVsNotNilBundleId() {
        let a = AppInfo(pid: 123, appName: "Test", bundleId: nil)
        let b = AppInfo(pid: 123, appName: "Test", bundleId: "com.test")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - JSON snake_case keys

    func testJSON_snakeCaseKeys() throws {
        let info = AppInfo(pid: 1, appName: "Safari", bundleId: "com.apple.Safari")
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Keys should be snake_case
        XCTAssertNotNil(json["app_name"])
        XCTAssertNotNil(json["bundle_id"])
        // Keys should NOT be camelCase
        XCTAssertNil(json["appName"])
        XCTAssertNil(json["bundleId"])
    }

    func testJSON_pidIsInt() throws {
        let info = AppInfo(pid: 42, appName: "Test", bundleId: nil)
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["pid"] as? Int, 42)
    }
}
