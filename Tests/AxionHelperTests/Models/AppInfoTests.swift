import Foundation
import Testing
@testable import AxionHelper

@Suite("AppInfo")
struct AppInfoTests {

    @Test("codable round trip")
    func codableRoundTrip() throws {
        let original = AppInfo(pid: 1234, appName: "Calculator", bundleId: "com.apple.calculator")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppInfo.self, from: data)
        #expect(decoded == original)
    }

    @Test("codable round trip with nil bundleId")
    func codableRoundTripNilBundleId() throws {
        let original = AppInfo(pid: 5678, appName: "SomeApp", bundleId: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppInfo.self, from: data)
        #expect(decoded == original)
    }

    @Test("JSON keys present")
    func jsonKeys() throws {
        let info = AppInfo(pid: 99, appName: "Finder", bundleId: "com.apple.finder")
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["pid"] != nil)
        #expect(json?["app_name"] != nil)
        #expect(json?["bundle_id"] != nil)
    }

    // MARK: - Equality

    @Test("equality: same values")
    func equalitySame() {
        let a = AppInfo(pid: 123, appName: "Test", bundleId: "com.test")
        let b = AppInfo(pid: 123, appName: "Test", bundleId: "com.test")
        #expect(a == b)
    }

    @Test("equality: different pid")
    func equalityDifferentPid() {
        let a = AppInfo(pid: 123, appName: "Test", bundleId: nil)
        let b = AppInfo(pid: 456, appName: "Test", bundleId: nil)
        #expect(a != b)
    }

    @Test("equality: different name")
    func equalityDifferentName() {
        let a = AppInfo(pid: 123, appName: "Test1", bundleId: nil)
        let b = AppInfo(pid: 123, appName: "Test2", bundleId: nil)
        #expect(a != b)
    }

    @Test("equality: different bundleId")
    func equalityDifferentBundleId() {
        let a = AppInfo(pid: 123, appName: "Test", bundleId: "com.a")
        let b = AppInfo(pid: 123, appName: "Test", bundleId: "com.b")
        #expect(a != b)
    }

    @Test("equality: nil vs non-nil bundleId")
    func equalityNilVsNotNilBundleId() {
        let a = AppInfo(pid: 123, appName: "Test", bundleId: nil)
        let b = AppInfo(pid: 123, appName: "Test", bundleId: "com.test")
        #expect(a != b)
    }

    // MARK: - JSON snake_case keys

    @Test("JSON uses snake_case keys")
    func jsonSnakeCaseKeys() throws {
        let info = AppInfo(pid: 1, appName: "Safari", bundleId: "com.apple.Safari")
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["app_name"] != nil)
        #expect(json["bundle_id"] != nil)
        #expect(json["appName"] == nil)
        #expect(json["bundleId"] == nil)
    }

    @Test("JSON pid is Int")
    func jsonPidIsInt() throws {
        let info = AppInfo(pid: 42, appName: "Test", bundleId: nil)
        let data = try JSONEncoder().encode(info)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["pid"] as? Int == 42)
    }
}
