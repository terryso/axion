import Testing
import Foundation

import AxionCore
@testable import AxionCLI

@Suite("Storage Approval Input Builder")
struct StorageApprovalInputTests {

    @Test("build execute_storage_plan maps items with low risk")
    func buildStoragePlan() throws {
        let params: [String: Any] = [
            "operation_id": "op1",
            "user_request": "整理下载",
            "items": [
                ["action": "move", "source": "/a", "target": "/b", "size_bytes": 10, "reason": "大文件"],
                ["action": "trash", "source": "/c"],
            ]
        ]
        let parsed = try #require(StorageApprovalInput.build(toolName: "execute_storage_plan", params: params))
        #expect(parsed.operationId == "op1")
        #expect(parsed.userRequest == "整理下载")
        #expect(parsed.items.count == 2)
        #expect(parsed.items[0].action == .move)
        #expect(parsed.items[0].key == "/a")
        #expect(parsed.items[0].targetPath == "/b")
        #expect(parsed.items[0].riskLevel == .low)
        #expect(parsed.requiresTypedConfirmation == false)
        #expect(parsed.typedConfirmationCandidates == nil)
    }

    @Test("build execute_storage_plan returns nil on empty items")
    func buildStoragePlanEmpty() {
        let params: [String: Any] = ["operation_id": "op1", "items": []]
        #expect(StorageApprovalInput.build(toolName: "execute_storage_plan", params: params) == nil)
    }

    @Test("build execute_app_uninstall marks bundle as typed/explicit + maps support items")
    func buildAppUninstall() throws {
        let params: [String: Any] = [
            "operation_id": "op1",
            "app": ["bundle_path": "/Applications/Foo.app", "bundle_identifier": "com.foo", "display_name": "Foo"],
            "uninstall_bundle": true,
            "support_data_items": [
                ["category": "cache", "path": "/Users/a/Library/Caches/com.foo", "data_risk": "low"],
                ["category": "preferences", "path": "/Users/a/Library/Preferences/com.foo.plist", "data_risk": "high"],
            ]
        ]
        let parsed = try #require(StorageApprovalInput.build(toolName: "execute_app_uninstall", params: params))
        #expect(parsed.requiresTypedConfirmation == true)
        #expect(parsed.typedConfirmationCandidates == ["Foo", "com.foo"])
        #expect(parsed.items.count == 3)   // bundle + 2 support

        let bundle = try #require(parsed.items.first { $0.action == .uninstallApp })
        #expect(bundle.key == "/Applications/Foo.app")
        #expect(bundle.requiresExplicitApproval == true)
        #expect(bundle.riskLevel == .high)

        let highRisk = try #require(parsed.items.first { $0.sourcePath.contains("Preferences") })
        #expect(highRisk.dataRisk == .high)
        #expect(highRisk.riskLevel == .high)
        #expect(highRisk.action == .trash)
    }

    @Test("build execute_app_uninstall without bundle uninstall needs no typed confirmation")
    func buildAppUninstallSupportOnly() throws {
        let params: [String: Any] = [
            "operation_id": "op1",
            "app": ["bundle_path": "/Applications/Foo.app", "bundle_identifier": "com.foo"],
            "uninstall_bundle": false,
            "support_data_items": [["category": "cache", "path": "/x", "data_risk": "low"]]
        ]
        let parsed = try #require(StorageApprovalInput.build(toolName: "execute_app_uninstall", params: params))
        #expect(parsed.requiresTypedConfirmation == false)
        #expect(parsed.typedConfirmationCandidates == nil)
        #expect(parsed.items.count == 1)
        #expect(parsed.items.first?.action == .trash)
    }

    @Test("build returns nil for non-storage tool name")
    func buildNonStorage() {
        #expect(StorageApprovalInput.build(toolName: "Bash", params: ["command": "ls"]) == nil)
    }

    @Test("build execute_app_uninstall returns nil when missing app")
    func buildAppUninstallNoApp() {
        let params: [String: Any] = ["operation_id": "op1", "app": ["display_name": "Foo"], "uninstall_bundle": true]
        #expect(StorageApprovalInput.build(toolName: "execute_app_uninstall", params: params) == nil)
    }
}
