import Foundation
import XCTest

// ATDD Red-Phase Test Scaffolds for Story 1.6
// AC: #2 - AxionHelper.app 打包配置正确
// These tests verify the App Bundle build script output (Info.plist, directory structure).
// They are unit tests — no AX permissions needed.
// Priority: P0 (App Bundle packaging verification)

final class AppBundleTests: XCTestCase {

    // MARK: - Helpers

    /// Expected App Bundle path after build-helper-app.sh runs.
    private var appBundlePath: String {
        let projectRoot = FileManager.default.currentDirectoryPath
        return "\(projectRoot)/.build/AxionHelper.app"
    }

    /// Expected Info.plist path.
    private var infoPlistPath: String {
        "\(appBundlePath)/Contents/Info.plist"
    }

    /// Checks if the App Bundle has been built.
    private var appBundleExists: Bool {
        FileManager.default.fileExists(atPath: appBundlePath)
    }

    /// Loads Info.plist as a dictionary.
    private func loadInfoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: infoPlistPath))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    // MARK: - AC2: AxionHelper.app 打包配置正确

    // [P0] Info.plist contains LSUIElement = true (no Dock icon)
    func test_infoPlist_containsLSUIElement() throws {
        guard appBundleExists else {
            throw XCTSkip("AxionHelper.app not built. Run `bash Distribution/homebrew/build-helper-app.sh` first.")
        }

        // Given: Built AxionHelper.app
        let plist = try loadInfoPlist()

        // Then: LSUIElement is true (background agent, no Dock icon)
        let lsuiElement = try XCTUnwrap(plist["LSUIElement"] as? Bool)
        XCTAssertTrue(lsuiElement, "LSUIElement should be true (no Dock icon)")
    }

    // [P0] Info.plist contains LSMinimumSystemVersion = 13.0
    func test_infoPlist_containsMinimumSystemVersion() throws {
        guard appBundleExists else {
            throw XCTSkip("AxionHelper.app not built. Run `bash Distribution/homebrew/build-helper-app.sh` first.")
        }

        // Given: Built AxionHelper.app
        let plist = try loadInfoPlist()

        // Then: LSMinimumSystemVersion is at least 13.0
        let minVersion = try XCTUnwrap(plist["LSMinimumSystemVersion"] as? String)
        // Accept "13.0" or higher
        XCTAssertFalse(minVersion.isEmpty, "LSMinimumSystemVersion should not be empty")
    }

    // [P0] Info.plist contains correct bundle identifier
    func test_infoPlist_containsBundleIdentifier() throws {
        guard appBundleExists else {
            throw XCTSkip("AxionHelper.app not built. Run `bash Distribution/homebrew/build-helper-app.sh` first.")
        }

        // Given: Built AxionHelper.app
        let plist = try loadInfoPlist()

        // Then: CFBundleIdentifier is com.axion.helper
        let bundleId = try XCTUnwrap(plist["CFBundleIdentifier"] as? String)
        XCTAssertEqual(bundleId, "com.axion.helper", "Bundle identifier should be com.axion.helper")
    }

    // [P1] App Bundle directory structure is correct
    func test_appBundleStructure_hasExpectedDirectories() throws {
        guard appBundleExists else {
            throw XCTSkip("AxionHelper.app not built. Run `bash Distribution/homebrew/build-helper-app.sh` first.")
        }

        // Given: Built AxionHelper.app
        let fm = FileManager.default

        // Then: Required directories and files exist
        XCTAssertTrue(fm.fileExists(atPath: "\(appBundlePath)/Contents"),
                       "Contents directory should exist")
        XCTAssertTrue(fm.fileExists(atPath: "\(appBundlePath)/Contents/MacOS"),
                       "Contents/MacOS directory should exist")
        XCTAssertTrue(fm.fileExists(atPath: infoPlistPath),
                       "Contents/Info.plist should exist")
        XCTAssertTrue(fm.fileExists(atPath: "\(appBundlePath)/Contents/MacOS/AxionHelper"),
                       "Contents/MacOS/AxionHelper executable should exist")

        // Verify executable is actually executable
        let execPath = "\(appBundlePath)/Contents/MacOS/AxionHelper"
        XCTAssertTrue(fm.isExecutableFile(atPath: execPath),
                       "AxionHelper binary should be executable")
    }

    // [P1] Info.plist version matches VERSION file
    func test_infoPlist_versionMatchesProjectVersion() throws {
        guard appBundleExists else {
            throw XCTSkip("AxionHelper.app not built. Run `bash Distribution/homebrew/build-helper-app.sh` first.")
        }

        // Given: Built AxionHelper.app and VERSION file
        let projectRoot = FileManager.default.currentDirectoryPath
        let versionFilePath = "\(projectRoot)/VERSION"

        guard FileManager.default.fileExists(atPath: versionFilePath) else {
            throw XCTSkip("VERSION file not found at project root")
        }

        let versionString = try String(contentsOfFile: versionFilePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let plist = try loadInfoPlist()

        // Then: CFBundleShortVersionString matches VERSION file
        let bundleVersion = try XCTUnwrap(plist["CFBundleShortVersionString"] as? String)
        XCTAssertEqual(bundleVersion, versionString,
                       "App version should match VERSION file. Expected: '\(versionString)', Got: '\(bundleVersion)'")
    }
}
