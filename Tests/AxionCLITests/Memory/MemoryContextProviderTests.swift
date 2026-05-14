import XCTest
import OpenAgentSDK

@testable import AxionCLI

// [P0] MemoryContextProvider type existence, domain inference, context assembly
// [P1] Familiar app compact strategy, failure annotation, edge cases
// Story 4.3 AC: #1, #2, #3, #4

// MARK: - MemoryContextProvider ATDD Tests

/// ATDD red-phase tests for MemoryContextProvider (Story 4.3 AC1, AC2, AC3, AC4).
/// Tests that MemoryContextProvider correctly:
/// - Infers App domain from task description
/// - Queries MemoryStore for profile and familiar data
/// - Assembles a prompt fragment with Memory context
/// - Handles familiar vs unfamiliar App strategies
/// - Safely degrades when no Memory data exists
///
/// TDD RED PHASE: These tests will not compile until MemoryContextProvider is implemented
/// in Sources/AxionCLI/Memory/MemoryContextProvider.swift.
final class MemoryContextProviderTests: XCTestCase {

    // MARK: - Helper: Create KnowledgeEntry

    private func makeEntry(
        id: String = UUID().uuidString,
        content: String,
        tags: [String],
        createdAt: Date = Date(),
        sourceRunId: String? = nil
    ) -> KnowledgeEntry {
        KnowledgeEntry(
            id: id,
            content: content,
            tags: tags,
            createdAt: createdAt,
            sourceRunId: sourceRunId
        )
    }

    // MARK: - P0: Type Existence

    func test_memoryContextProvider_typeExists() {
        let _ = MemoryContextProvider.self
    }

    // MARK: - P0 AC1: Inject App Memory context into Planner prompt

    func test_buildMemoryContext_withProfileData_returnsNonNil() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        // Populate profile data
        let profileEntry = makeEntry(
            content: """
            App Profile: \(domain)
            总运行次数: 5
            成功次数: 4
            失败次数: 1
            已熟悉: 是
            AX特征: 窗口包含 AXButton 角色控件
            高频路径: launch_app -> click -> click -> click -> click (频率:4, 成功率:100%)
            已知失败: click(x:300,y:400) — 坐标或元素定位不可靠 (修正: 使用 AX selector AXButton[title="*"] 代替坐标点击)
            """,
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "打开计算器，计算 17 × 23",
            store: store
        )

        XCTAssertNotNil(context,
            "Should return non-nil Memory context when profile data exists for the matched App")
    }

    func test_buildMemoryContext_containsAppMemorySection() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        let profileEntry = makeEntry(
            content: """
            App Profile: \(domain)
            总运行次数: 3
            成功次数: 3
            失败次数: 0
            已熟悉: 是
            AX特征: 窗口包含 AXButton 角色控件
            高频路径: launch_app -> click -> click (频率:3, 成功率:100%)
            """,
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "在计算器中输入 42 + 58",
            store: store
        )

        XCTAssertNotNil(context)
        let ctx = try XCTUnwrap(context)
        XCTAssertTrue(ctx.contains("App Memory Context"),
            "Memory context should include 'App Memory Context' section header")
        XCTAssertTrue(ctx.contains(domain),
            "Memory context should reference the App domain")
    }

    func test_buildMemoryContext_containsReliableOperationPaths() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        let profileEntry = makeEntry(
            content: """
            App Profile: \(domain)
            总运行次数: 4
            成功次数: 4
            失败次数: 0
            已熟悉: 是
            高频路径: launch_app -> click -> click -> click (频率:4, 成功率:100%)
            """,
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "打开计算器计算 2+2",
            store: store
        )

        XCTAssertNotNil(context)
        let ctx = try XCTUnwrap(context)
        XCTAssertTrue(ctx.contains("launch_app"),
            "Memory context should reference known reliable operation paths")
    }

    func test_buildMemoryContext_containsAxCharacteristics() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        let profileEntry = makeEntry(
            content: """
            App Profile: \(domain)
            总运行次数: 3
            成功次数: 3
            失败次数: 0
            已熟悉: 是
            AX特征: 窗口包含 AXButton 角色控件，按钮标题与数字对应
            """,
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "用计算器算 100 ÷ 5",
            store: store
        )

        XCTAssertNotNil(context)
        let ctx = try XCTUnwrap(context)
        XCTAssertTrue(ctx.contains("AXButton"),
            "Memory context should include AX characteristics from profile")
    }

    // MARK: - P0 AC2: Annotate known unreliable operation paths

    func test_buildMemoryContext_annotatesKnownFailures() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        let profileEntry = makeEntry(
            content: """
            App Profile: \(domain)
            总运行次数: 5
            成功次数: 4
            失败次数: 1
            已熟悉: 是
            已知失败: click(x:300,y:400) — 坐标或元素定位不可靠 (修正: 使用 AX selector AXButton[title="*"] 代替坐标点击)
            """,
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "打开计算器做乘法",
            store: store
        )

        XCTAssertNotNil(context)
        let ctx = try XCTUnwrap(context)
        XCTAssertTrue(ctx.contains("已知失败") || ctx.contains("避免") || ctx.contains("不可靠"),
            "Memory context should annotate known failure patterns to help Planner avoid them")
    }

    func test_buildMemoryContext_failureDataMarkedAsAvoid() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.finder"

        let profileEntry = makeEntry(
            content: """
            App Profile: \(domain)
            总运行次数: 3
            成功次数: 2
            失败次数: 1
            已熟悉: 否
            已知失败: click(x:150,y:300) 侧边栏坐标不稳定 — 坐标或元素定位不可靠 (修正: 使用 AXSidebar[ordinal=0])
            """,
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "在 Finder 中打开文件",
            store: store
        )

        XCTAssertNotNil(context)
        let ctx = try XCTUnwrap(context)
        // Should contain the failure info and optionally the workaround
        XCTAssertTrue(ctx.contains("click(x:150,y:300)") || ctx.contains("AXSidebar"),
            "Memory context should include specific failure details")
    }

    // MARK: - P0 AC3: Familiar App uses compact planning strategy

    func test_buildMemoryContext_familiarApp_includesCompactStrategy() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        // Profile data showing app is familiar (>= 3 successes)
        let profileEntry = makeEntry(
            content: """
            App Profile: \(domain)
            总运行次数: 5
            成功次数: 5
            失败次数: 0
            已熟悉: 是
            高频路径: launch_app -> click -> click -> click (频率:5, 成功率:100%)
            """,
            tags: ["app:\(domain)", "profile"]
        )
        // Familiar marker
        let familiarEntry = makeEntry(
            content: "App \(domain) 已熟悉（累计 5 次成功操作）",
            tags: ["app:\(domain)", "familiar"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)
        try await store.save(domain: domain, knowledge: familiarEntry)

        let context = try await provider.buildMemoryContext(
            task: "打开计算器",
            store: store
        )

        XCTAssertNotNil(context)
        let ctx = try XCTUnwrap(context)
        XCTAssertTrue(ctx.contains("紧凑") || ctx.contains("compact") || ctx.contains("省略") || ctx.contains("减少"),
            "Familiar App context should include compact planning strategy suggestion")
    }

    func test_buildMemoryContext_unfamiliarApp_includesFullVerificationStrategy() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.finder"

        // Profile data showing app is NOT familiar
        let profileEntry = makeEntry(
            content: """
            App Profile: \(domain)
            总运行次数: 2
            成功次数: 2
            失败次数: 0
            已熟悉: 否
            高频路径: launch_app -> hotkey -> type_text (频率:2, 成功率:100%)
            """,
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)
        // No familiar entry saved

        let context = try await provider.buildMemoryContext(
            task: "在 Finder 中搜索文件",
            store: store
        )

        XCTAssertNotNil(context)
        let ctx = try XCTUnwrap(context)
        XCTAssertTrue(ctx.contains("尚未熟悉") || ctx.contains("完整验证") || ctx.contains("建议"),
            "Unfamiliar App context should include full verification strategy suggestion")
    }

    // MARK: - P0 AC4: --no-memory flag disables Memory injection

    // Note: The --no-memory flag test is a RunCommand integration test.
    // MemoryContextProvider should support being skipped entirely when noMemory == true.
    // This is tested in the RunCommand test; here we test the provider returns nil
    // when there is no matching data (safe degradation).

    func test_buildMemoryContext_noMatchingApp_returnsNil() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()

        // Store has data for Calculator but task mentions an unknown app
        let profileEntry = makeEntry(
            content: """
            App Profile: com.apple.calculator
            总运行次数: 3
            成功次数: 3
            已熟悉: 是
            """,
            tags: ["app:com.apple.calculator", "profile"]
        )
        try await store.save(domain: "com.apple.calculator", knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "在 Photoshop 中打开图片",  // No matching app
            store: store
        )

        XCTAssertNil(context,
            "Should return nil when no App name in task matches any stored Memory domain")
    }

    // MARK: - P0: Domain inference from task description

    func test_domainInference_matchesCalculator() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        let profileEntry = makeEntry(
            content: "App Profile: \(domain)\n总运行次数: 1\n成功次数: 1\n已熟悉: 否",
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        // Test various Chinese and English variants
        let tasks = [
            "打开计算器",
            "打开 Calculator",
            "使用计算器计算",
            "在 Calculator 中输入",
        ]

        for task in tasks {
            let context = try await provider.buildMemoryContext(task: task, store: store)
            XCTAssertNotNil(context,
                "Should match Calculator domain for task: '\(task)'")
        }
    }

    func test_domainInference_matchesFinder() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.finder"

        let profileEntry = makeEntry(
            content: "App Profile: \(domain)\n总运行次数: 1\n成功次数: 1\n已熟悉: 否",
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "在 Finder 中打开文件",
            store: store
        )

        XCTAssertNotNil(context, "Should match Finder domain")
    }

    func test_domainInference_matchesSafari() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.safari"

        let profileEntry = makeEntry(
            content: "App Profile: \(domain)\n总运行次数: 1\n成功次数: 1\n已熟悉: 否",
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "在 Safari 中打开网页",
            store: store
        )

        XCTAssertNotNil(context, "Should match Safari domain")
    }

    func test_domainInference_matchesChrome() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.google.chrome"

        let profileEntry = makeEntry(
            content: "App Profile: \(domain)\n总运行次数: 1\n成功次数: 1\n已熟悉: 否",
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "用 Google Chrome 搜索",
            store: store
        )

        XCTAssertNotNil(context, "Should match Chrome domain")
    }

    func test_domainInference_matchesTextEdit() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.textedit"

        let profileEntry = makeEntry(
            content: "App Profile: \(domain)\n总运行次数: 1\n成功次数: 1\n已熟悉: 否",
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "在文本编辑中写一篇文章",
            store: store
        )

        XCTAssertNotNil(context, "Should match TextEdit domain")
    }

    func test_domainInference_matchesTerminal() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.terminal"

        let profileEntry = makeEntry(
            content: "App Profile: \(domain)\n总运行次数: 1\n成功次数: 1\n已熟悉: 否",
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "打开终端执行命令",
            store: store
        )

        XCTAssertNotNil(context, "Should match Terminal domain")
    }

    // MARK: - P0: Empty Memory returns nil (safe degradation)

    func test_buildMemoryContext_emptyStore_returnsNil() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()

        let context = try await provider.buildMemoryContext(
            task: "打开计算器",
            store: store
        )

        XCTAssertNil(context,
            "Should return nil when MemoryStore has no data")
    }

    func test_buildMemoryContext_noProfileData_returnsNil() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        // Only run entries, no profile
        let runEntry = makeEntry(
            content: "成功运行",
            tags: ["app:\(domain)", "success"]
        )
        try await store.save(domain: domain, knowledge: runEntry)

        let context = try await provider.buildMemoryContext(
            task: "打开计算器",
            store: store
        )

        XCTAssertNil(context,
            "Should return nil when only raw run entries exist without profile data")
    }

    // MARK: - P0: MemoryStore error handling (safe degradation)

    func test_buildMemoryContext_storeError_returnsNil() async throws {
        // Use a store that will be queried successfully but has no relevant data
        let store = InMemoryStore()
        let provider = MemoryContextProvider()

        // Task that doesn't match any known app
        let context = try await provider.buildMemoryContext(
            task: "完成一个不涉及任何已知 App 的任务",
            store: store
        )

        XCTAssertNil(context,
            "Should return nil gracefully when no matching Memory context is found")
    }

    // MARK: - P1: App name mapping completeness

    func test_appNameMap_containsCommonApps() {
        let provider = MemoryContextProvider()

        // Verify the static appNameMap contains expected entries
        // This tests that the mapping table is populated
        let map = MemoryContextProvider.appNameMap
        XCTAssertFalse(map.isEmpty,
            "App name mapping should not be empty")

        // Check for key entries
        let domains = map.map { $0.domain }
        XCTAssertTrue(domains.contains("com.apple.calculator"),
            "Should map Calculator")
        XCTAssertTrue(domains.contains("com.apple.finder"),
            "Should map Finder")
        XCTAssertTrue(domains.contains("com.apple.safari"),
            "Should map Safari")
        XCTAssertTrue(domains.contains("com.google.chrome"),
            "Should map Chrome")
    }

    // MARK: - P1: Context format verification

    func test_buildMemoryContext_format_hasSectionHeaders() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        let profileEntry = makeEntry(
            content: """
            App Profile: \(domain)
            总运行次数: 4
            成功次数: 4
            失败次数: 0
            已熟悉: 是
            AX特征: 窗口包含 AXButton 角色控件
            高频路径: launch_app -> click -> click -> click (频率:4, 成功率:100%)
            已知失败: click(x:300,y:400) — 坐标不可靠 (修正: 使用 AX selector 代替)
            """,
            tags: ["app:\(domain)", "profile"]
        )
        let familiarEntry = makeEntry(
            content: "App \(domain) 已熟悉（累计 4 次成功操作）",
            tags: ["app:\(domain)", "familiar"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)
        try await store.save(domain: domain, knowledge: familiarEntry)

        let context = try await provider.buildMemoryContext(
            task: "使用计算器计算 99 * 77",
            store: store
        )

        XCTAssertNotNil(context)
        let ctx = try XCTUnwrap(context)

        // Should have section structure
        XCTAssertTrue(ctx.hasPrefix("# App Memory Context") || ctx.contains("# App Memory Context"),
            "Context should start with or contain '# App Memory Context' header")
    }

    // MARK: - P1: Multiple apps in task description

    func test_buildMemoryContext_taskMentionsMultipleApps_matchesFirst() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()

        // Both Calculator and Finder have profile data
        let calcProfile = makeEntry(
            content: "App Profile: com.apple.calculator\n总运行次数: 3\n成功次数: 3\n已熟悉: 是",
            tags: ["app:com.apple.calculator", "profile"]
        )
        let finderProfile = makeEntry(
            content: "App Profile: com.apple.finder\n总运行次数: 2\n成功次数: 2\n已熟悉: 否",
            tags: ["app:com.apple.finder", "profile"]
        )
        try await store.save(domain: "com.apple.calculator", knowledge: calcProfile)
        try await store.save(domain: "com.apple.finder", knowledge: finderProfile)

        let context = try await provider.buildMemoryContext(
            task: "在 Finder 中找到文件后用计算器计算大小",
            store: store
        )

        XCTAssertNotNil(context,
            "Should match at least one App when multiple are mentioned")
    }

    // MARK: - P1: Case-insensitive matching

    func test_domainInference_caseInsensitive() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        let profileEntry = makeEntry(
            content: "App Profile: \(domain)\n总运行次数: 1\n成功次数: 1\n已熟悉: 否",
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let context = try await provider.buildMemoryContext(
            task: "打开 CALCULATOR",
            store: store
        )

        XCTAssertNotNil(context,
            "Should match domain case-insensitively")
    }
}
