import Testing
import Foundation

@testable import AxionCLI
import AxionCore

@Suite("App Discovery (pure functions)")
struct AppDiscoveryTests {

    // MARK: - classifyMatch

    @Test("classifyMatch: exact bundle identifier is high")
    func classifyExactBundleId() {
        #expect(AppDiscoveryService.classifyMatch(
            query: "com.example.foo",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .high)
    }

    @Test("classifyMatch: exact display name (case-insensitive, .app stripped) is high")
    func classifyExactDisplayName() {
        #expect(AppDiscoveryService.classifyMatch(
            query: "Foo",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .high)
        #expect(AppDiscoveryService.classifyMatch(
            query: "foo",
            bundleIdentifier: "com.example.foo",
            displayName: "FOO"
        ) == .high)
        // query with .app suffix normalized
        #expect(AppDiscoveryService.classifyMatch(
            query: "Foo.app",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .high)
    }

    @Test("classifyMatch: bundle id prefix or name contains is medium")
    func classifyMedium() {
        // display name contains query
        #expect(AppDiscoveryService.classifyMatch(
            query: "Foo",
            bundleIdentifier: "com.example.foobar",
            displayName: "FooBar Pro"
        ) == .medium)
        // bundle id prefix (dotted reverse-DNS style)
        #expect(AppDiscoveryService.classifyMatch(
            query: "com.example",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .medium)
    }

    @Test("classifyMatch: unrelated input is low")
    func classifyLow() {
        #expect(AppDiscoveryService.classifyMatch(
            query: "TotallyDifferent",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .low)
        // empty query → low
        #expect(AppDiscoveryService.classifyMatch(
            query: "   ",
            bundleIdentifier: "com.example.foo",
            displayName: "Foo"
        ) == .low)
    }

    // MARK: - isSystemProtected

    @Test("isSystemProtected: Apple bundle id prefix is protected")
    func systemProtectedAppleBundleId() {
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/Applications/Calculator.app",
            bundleIdentifier: "com.apple.calculator"
        ) == true)
    }

    @Test("isSystemProtected: system directory paths are protected")
    func systemProtectedSystemDirs() {
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/System/Applications/Chess.app",
            bundleIdentifier: "com.apple.chess"
        ) == true)
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/Library/SomeApp.app",
            bundleIdentifier: "com.vendor.someapp"
        ) == true)
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/usr/local/bin/thing",
            bundleIdentifier: "com.vendor.thing"
        ) == true)
    }

    @Test("isSystemProtected: third-party app under /Applications is not protected")
    func systemNotProtectedThirdParty() {
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/Applications/Foo.app",
            bundleIdentifier: "com.example.foo"
        ) == false)
        #expect(AppDiscoveryService.isSystemProtected(
            bundlePath: "/Users/nick/Applications/Bar.app",
            bundleIdentifier: "com.other.bar"
        ) == false)
    }
}
