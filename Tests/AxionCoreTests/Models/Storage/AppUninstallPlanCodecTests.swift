import Testing
import Foundation

@testable import AxionCore

@Suite("App Uninstall Plan Codec")
struct AppUninstallPlanCodecTests {

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Enums (snake_case rawValue)

    @Test("AppMatchConfidence round-trip")
    func appMatchConfidenceRoundTrip() throws {
        #expect(AppMatchConfidence(rawValue: "high") == .high)
        #expect(AppMatchConfidence(rawValue: "medium") == .medium)
        #expect(AppMatchConfidence(rawValue: "low") == .low)
        #expect(try roundTrip(AppMatchConfidence.high) == .high)
    }

    @Test("SupportDataCategory rawValue uses snake_case")
    func supportDataCategorySnakeCase() throws {
        #expect(SupportDataCategory(rawValue: "http_storage") == .httpStorage)
        #expect(SupportDataCategory(rawValue: "web_kit") == .webKit)
        #expect(SupportDataCategory(rawValue: "saved_state") == .savedState)
        #expect(SupportDataCategory(rawValue: "application_scripts") == .applicationScripts)
        #expect(SupportDataCategory(rawValue: "application_support") == .applicationSupport)
        #expect(SupportDataCategory(rawValue: "group_container") == .groupContainer)
        #expect(SupportDataCategory(rawValue: "launch_agent") == .launchAgent)
        #expect(try roundTrip(SupportDataCategory.forbidden) == .forbidden)
        let data = try JSONEncoder().encode(SupportDataCategory.applicationSupport)
        #expect(String(data: data, encoding: .utf8) == "\"application_support\"")
    }

    @Test("AppUninstallMode rawValue uses snake_case")
    func appUninstallModeSnakeCase() throws {
        #expect(AppUninstallMode(rawValue: "scan_only") == .scanOnly)
        #expect(AppUninstallMode(rawValue: "uninstall_app_only") == .uninstallAppOnly)
        #expect(AppUninstallMode(rawValue: "uninstall_with_support_review") == .uninstallWithSupportReview)
        #expect(AppUninstallMode(rawValue: "review_support_data") == .reviewSupportData)
        #expect(AppUninstallMode(rawValue: "clean_approved_support_data") == .cleanApprovedSupportData)
        #expect(try roundTrip(AppUninstallMode.scanOnly) == .scanOnly)
    }

    @Test("DataLossRisk round-trip and max picks higher")
    func dataLossRiskRoundTripAndMax() throws {
        // Direct rawValue checks (case named `none` collides with Optional.none
        // when compared through the optional-returning init(rawValue:)).
        #expect(DataLossRisk.none.rawValue == "none")
        #expect(DataLossRisk(rawValue: "none") != nil)
        #expect(try roundTrip(DataLossRisk.high) == .high)
        #expect(DataLossRisk.max(DataLossRisk.none, .low) == .low)
        #expect(DataLossRisk.max(.high, .low) == .high)
        #expect(DataLossRisk.max(.medium, .medium) == .medium)
        #expect(DataLossRisk.max(DataLossRisk.none, DataLossRisk.none) == DataLossRisk.none)
    }

    // MARK: - AppCandidate

    @Test("AppCandidate round-trip preserves snake_case keys")
    func appCandidateRoundTrip() throws {
        let c = AppCandidate(
            displayName: "Foo",
            bundleIdentifier: "com.example.foo",
            bundlePath: "/Applications/Foo.app",
            version: "1.2.3",
            teamIdentifier: "ABCDE12345",
            sizeBytes: 4096,
            isRunning: true,
            isSystemProtected: false,
            matchConfidence: .high
        )
        let decoded = try roundTrip(c)
        #expect(decoded == c)
        #expect(decoded.sizeBytes == 4096)
        #expect(decoded.isRunning == true)
        #expect(decoded.matchConfidence == .high)

        // snake_case on the wire
        let data = try JSONEncoder().encode(c)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"bundle_identifier\""))
        #expect(json.contains("\"is_system_protected\""))
        #expect(json.contains("\"match_confidence\""))
    }

    @Test("AppCandidate decodes with defaults when fields missing")
    func appCandidateMissingDefaults() throws {
        let json = "{\"display_name\": \"Foo\"}".data(using: .utf8)!
        let c = try JSONDecoder().decode(AppCandidate.self, from: json)
        #expect(c.displayName == "Foo")
        #expect(c.bundleIdentifier == "")
        #expect(c.sizeBytes == 0)
        #expect(c.isRunning == false)
        #expect(c.isSystemProtected == false)
        #expect(c.matchConfidence == .low)
        #expect(c.teamIdentifier == nil)
    }

    // MARK: - SupportDataItem

    @Test("SupportDataItem round-trip")
    func supportDataItemRoundTrip() throws {
        let item = SupportDataItem(
            category: .container,
            path: "/Users/a/Library/Containers/com.example.foo",
            sizeBytes: 999,
            matchEvidence: StorageEvidence(rule: "bundle_id_keyed", source: "container", confidence: .high),
            matchConfidence: .high,
            dataRisk: .high,
            defaultSelected: false,
            requiresExplicitApproval: true
        )
        let decoded = try roundTrip(item)
        #expect(decoded == item)
        #expect(decoded.defaultSelected == false)
        #expect(decoded.requiresExplicitApproval == true)

        let data = try JSONEncoder().encode(item)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"data_risk\""))
        #expect(json.contains("\"default_selected\""))
        #expect(json.contains("\"requires_explicit_approval\""))
    }

    @Test("SupportDataItem decodes with defaults when fields missing")
    func supportDataItemMissingDefaults() throws {
        let json = "{\"path\": \"/x\"}".data(using: .utf8)!
        let item = try JSONDecoder().decode(SupportDataItem.self, from: json)
        #expect(item.path == "/x")
        #expect(item.category == .cache)
        #expect(item.defaultSelected == false)
        #expect(item.dataRisk == .medium)
    }

    // MARK: - ExternalUninstallHint

    @Test("ExternalUninstallHint round-trip and defaults")
    func externalHintRoundTrip() throws {
        let hint = ExternalUninstallHint(
            source: "pkg_receipt",
            detail: "com.example.foo.bom",
            paths: ["/var/db/receipts/com.example.foo.bom"],
            confidence: .medium
        )
        let decoded = try roundTrip(hint)
        #expect(decoded == hint)

        let json = "{\"source\": \"homebrew_cask\"}".data(using: .utf8)!
        let h = try JSONDecoder().decode(ExternalUninstallHint.self, from: json)
        #expect(h.source == "homebrew_cask")
        #expect(h.paths == [])
        #expect(h.confidence == .medium)
    }

    // MARK: - AppUninstallPlan

    @Test("AppUninstallPlan round-trip preserves all fields")
    func planRoundTrip() throws {
        let plan = AppUninstallPlan(
            app: AppCandidate(displayName: "Foo", bundleIdentifier: "com.example.foo", bundlePath: "/Applications/Foo.app", version: "1.0", sizeBytes: 100, isRunning: false, isSystemProtected: false, matchConfidence: .high),
            candidates: [
                AppCandidate(displayName: "Foo", bundleIdentifier: "com.example.foo", bundlePath: "/Applications/Foo.app", version: "1.0", sizeBytes: 100, isRunning: false, isSystemProtected: false, matchConfidence: .high),
            ],
            uninstallMode: .uninstallWithSupportReview,
            supportDataItems: [
                SupportDataItem(category: .cache, path: "/Users/a/Library/Caches/com.example.foo", sizeBytes: 50, matchEvidence: StorageEvidence(rule: "bundle_id_keyed", source: "cache"), matchConfidence: .high, dataRisk: .low, defaultSelected: true, requiresExplicitApproval: false),
            ],
            hintOnlySupportDataItems: [
                SupportDataItem(category: .logs, path: "/Users/a/Library/Logs/Fooish", sizeBytes: 10, matchEvidence: StorageEvidence(rule: "name_similarity", source: "logs"), matchConfidence: .low, dataRisk: .low, defaultSelected: false, requiresExplicitApproval: false),
            ],
            dataLossRisk: .low,
            requiresTypedConfirmation: false,
            blockedReasons: [],
            externalUninstallHints: [
                ExternalUninstallHint(source: "homebrew_cask", detail: "zap", paths: []),
            ]
        )
        let decoded = try roundTrip(plan)
        #expect(decoded == plan)
        #expect(decoded.supportDataItems.count == 1)
        #expect(decoded.hintOnlySupportDataItems.first?.matchConfidence == .low)
    }

    @Test("AppUninstallPlan decodes with defaults when fields missing")
    func planMissingDefaults() throws {
        let json = "{}".data(using: .utf8)!
        let plan = try JSONDecoder().decode(AppUninstallPlan.self, from: json)
        #expect(plan.app.bundleIdentifier == "")
        #expect(plan.candidates == [])
        #expect(plan.uninstallMode == .uninstallWithSupportReview)
        #expect(plan.supportDataItems == [])
        #expect(plan.hintOnlySupportDataItems == [])
        #expect(plan.dataLossRisk == .none)
        #expect(plan.requiresTypedConfirmation == false)
        #expect(plan.blockedReasons == [])
        #expect(plan.externalUninstallHints == [])
    }
}
