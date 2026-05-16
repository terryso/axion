import Foundation
import Testing

@Suite("AppBundle")
struct AppBundleTests {

    private var appBundlePath: String {
        let projectRoot = FileManager.default.currentDirectoryPath
        return "\(projectRoot)/.build/AxionHelper.app"
    }

    private var infoPlistPath: String {
        "\(appBundlePath)/Contents/Info.plist"
    }

    private var appBundleExists: Bool {
        FileManager.default.fileExists(atPath: appBundlePath)
    }

    private func loadInfoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: infoPlistPath))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test("Info.plist contains LSUIElement = true")
    func infoPlistContainsLSUIElement() throws {
        guard appBundleExists else { return }

        let plist = try loadInfoPlist()
        let lsuiElement = try #require(plist["LSUIElement"] as? Bool)
        #expect(lsuiElement)
    }

    @Test("Info.plist contains minimum system version")
    func infoPlistContainsMinimumSystemVersion() throws {
        guard appBundleExists else { return }

        let plist = try loadInfoPlist()
        let minVersion = try #require(plist["LSMinimumSystemVersion"] as? String)
        #expect(!minVersion.isEmpty)
    }

    @Test("Info.plist contains correct bundle identifier")
    func infoPlistContainsBundleIdentifier() throws {
        guard appBundleExists else { return }

        let plist = try loadInfoPlist()
        let bundleId = try #require(plist["CFBundleIdentifier"] as? String)
        #expect(bundleId == "com.axion.AxionHelper")
    }

    @Test("App Bundle directory structure is correct")
    func appBundleStructureHasExpectedDirectories() throws {
        guard appBundleExists else { return }

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: "\(appBundlePath)/Contents"))
        #expect(fm.fileExists(atPath: "\(appBundlePath)/Contents/MacOS"))
        #expect(fm.fileExists(atPath: infoPlistPath))
        #expect(fm.fileExists(atPath: "\(appBundlePath)/Contents/MacOS/AxionHelper"))

        let execPath = "\(appBundlePath)/Contents/MacOS/AxionHelper"
        #expect(fm.isExecutableFile(atPath: execPath))
    }

    @Test("Info.plist version matches project version")
    func infoPlistVersionMatchesProjectVersion() throws {
        guard appBundleExists else { return }

        let projectRoot = FileManager.default.currentDirectoryPath
        let versionFilePath = "\(projectRoot)/VERSION"
        guard FileManager.default.fileExists(atPath: versionFilePath) else { return }

        let versionString = try String(contentsOfFile: versionFilePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let plist = try loadInfoPlist()
        let bundleVersion = try #require(plist["CFBundleShortVersionString"] as? String)
        #expect(bundleVersion == versionString)
    }
}
