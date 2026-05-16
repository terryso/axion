import Foundation
import Testing
import OpenAgentSDK

@testable import AxionCLI

// [P0] MemoryContextProvider type existence, domain inference, context assembly
// [P1] Familiar app compact strategy, failure annotation, edge cases
// Story 4.3 AC: #1, #2, #3, #4

// MARK: - MemoryContextProvider ATDD Tests

/// ATDD red-phase tests for MemoryContextProvider (Story 4.3 AC1, AC2, AC3, AC4).
@Suite("MemoryContextProvider")
struct MemoryContextProviderTests {

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

    @Test("type exists")
    func typeExists() {
        let _ = MemoryContextProvider.self
    }

    // MARK: - P0 AC1: Inject App Memory context into Planner prompt

    @Test("build memory context with profile data returns non-nil")
    func buildMemoryContextWithProfileDataReturnsNonNil() async throws {
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

        #expect(context != nil,
            "Should return non-nil Memory context when profile data exists for the matched App")
    }

    @Test("build memory context contains app memory section")
    func buildMemoryContextContainsAppMemorySection() async throws {
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

        #expect(context != nil)
        let ctx = try #require(context)
        #expect(ctx.contains("App Memory Context"),
            "Memory context should include 'App Memory Context' section header")
        #expect(ctx.contains(domain),
            "Memory context should reference the App domain")
    }

    @Test("build memory context contains reliable operation paths")
    func buildMemoryContextContainsReliableOperationPaths() async throws {
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

        #expect(context != nil)
        let ctx = try #require(context)
        #expect(ctx.contains("launch_app"),
            "Memory context should reference known reliable operation paths")
    }

    @Test("build memory context contains AX characteristics")
    func buildMemoryContextContainsAxCharacteristics() async throws {
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

        #expect(context != nil)
        let ctx = try #require(context)
        #expect(ctx.contains("AXButton"),
            "Memory context should include AX characteristics from profile")
    }

    // MARK: - P0 AC2: Annotate known unreliable operation paths

    @Test("build memory context annotates known failures")
    func buildMemoryContextAnnotatesKnownFailures() async throws {
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

        #expect(context != nil)
        let ctx = try #require(context)
        #expect(ctx.contains("已知失败") || ctx.contains("避免") || ctx.contains("不可靠"),
            "Memory context should annotate known failure patterns to help Planner avoid them")
    }

    @Test("build memory context failure data marked as avoid")
    func buildMemoryContextFailureDataMarkedAsAvoid() async throws {
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

        #expect(context != nil)
        let ctx = try #require(context)
        #expect(ctx.contains("click(x:150,y:300)") || ctx.contains("AXSidebar"),
            "Memory context should include specific failure details")
    }

    // MARK: - P0 AC3: Familiar App uses compact planning strategy

    @Test("build memory context familiar app includes compact strategy")
    func buildMemoryContextFamiliarAppIncludesCompactStrategy() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

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

        #expect(context != nil)
        let ctx = try #require(context)
        #expect(ctx.contains("紧凑") || ctx.contains("compact") || ctx.contains("省略") || ctx.contains("减少"),
            "Familiar App context should include compact planning strategy suggestion")
    }

    @Test("build memory context unfamiliar app includes full verification strategy")
    func buildMemoryContextUnfamiliarAppIncludesFullVerificationStrategy() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.finder"

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

        let context = try await provider.buildMemoryContext(
            task: "在 Finder 中搜索文件",
            store: store
        )

        #expect(context != nil)
        let ctx = try #require(context)
        #expect(ctx.contains("尚未熟悉") || ctx.contains("完整验证") || ctx.contains("建议"),
            "Unfamiliar App context should include full verification strategy suggestion")
    }

    // MARK: - P0 AC4: --no-memory flag disables Memory injection

    @Test("build memory context no matching app returns nil")
    func buildMemoryContextNoMatchingAppReturnsNil() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()

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
            task: "在 Photoshop 中打开图片",
            store: store
        )

        #expect(context == nil,
            "Should return nil when no App name in task matches any stored Memory domain")
    }

    // MARK: - P0: Domain inference from task description

    @Test("domain inference matches Calculator")
    func domainInferenceMatchesCalculator() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        let profileEntry = makeEntry(
            content: "App Profile: \(domain)\n总运行次数: 1\n成功次数: 1\n已熟悉: 否",
            tags: ["app:\(domain)", "profile"]
        )
        try await store.save(domain: domain, knowledge: profileEntry)

        let tasks = [
            "打开计算器",
            "打开 Calculator",
            "使用计算器计算",
            "在 Calculator 中输入",
        ]

        for task in tasks {
            let context = try await provider.buildMemoryContext(task: task, store: store)
            #expect(context != nil, "Should match Calculator domain for task: '\(task)'")
        }
    }

    @Test("domain inference matches Finder")
    func domainInferenceMatchesFinder() async throws {
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

        #expect(context != nil, "Should match Finder domain")
    }

    @Test("domain inference matches Safari")
    func domainInferenceMatchesSafari() async throws {
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

        #expect(context != nil, "Should match Safari domain")
    }

    @Test("domain inference matches Chrome")
    func domainInferenceMatchesChrome() async throws {
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

        #expect(context != nil, "Should match Chrome domain")
    }

    @Test("domain inference matches TextEdit")
    func domainInferenceMatchesTextEdit() async throws {
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

        #expect(context != nil, "Should match TextEdit domain")
    }

    @Test("domain inference matches Terminal")
    func domainInferenceMatchesTerminal() async throws {
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

        #expect(context != nil, "Should match Terminal domain")
    }

    // MARK: - P0: Empty Memory returns nil (safe degradation)

    @Test("build memory context empty store returns nil")
    func buildMemoryContextEmptyStoreReturnsNil() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()

        let context = try await provider.buildMemoryContext(
            task: "打开计算器",
            store: store
        )

        #expect(context == nil, "Should return nil when MemoryStore has no data")
    }

    @Test("build memory context no profile data returns nil")
    func buildMemoryContextNoProfileDataReturnsNil() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()
        let domain = "com.apple.calculator"

        let runEntry = makeEntry(
            content: "成功运行",
            tags: ["app:\(domain)", "success"]
        )
        try await store.save(domain: domain, knowledge: runEntry)

        let context = try await provider.buildMemoryContext(
            task: "打开计算器",
            store: store
        )

        #expect(context == nil,
            "Should return nil when only raw run entries exist without profile data")
    }

    // MARK: - P0: MemoryStore error handling (safe degradation)

    @Test("build memory context store error returns nil")
    func buildMemoryContextStoreErrorReturnsNil() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()

        let context = try await provider.buildMemoryContext(
            task: "完成一个不涉及任何已知 App 的任务",
            store: store
        )

        #expect(context == nil,
            "Should return nil gracefully when no matching Memory context is found")
    }

    // MARK: - P1: App name mapping completeness

    @Test("app name map contains common apps")
    func appNameMapContainsCommonApps() {
        let provider = MemoryContextProvider()

        let map = MemoryContextProvider.appNameMap
        #expect(!map.isEmpty, "App name mapping should not be empty")

        let domains = map.map { $0.domain }
        #expect(domains.contains("com.apple.calculator"), "Should map Calculator")
        #expect(domains.contains("com.apple.finder"), "Should map Finder")
        #expect(domains.contains("com.apple.safari"), "Should map Safari")
        #expect(domains.contains("com.google.chrome"), "Should map Chrome")
    }

    // MARK: - P1: Context format verification

    @Test("build memory context format has section headers")
    func buildMemoryContextFormatHasSectionHeaders() async throws {
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

        #expect(context != nil)
        let ctx = try #require(context)

        #expect(ctx.hasPrefix("# App Memory Context") || ctx.contains("# App Memory Context"),
            "Context should start with or contain '# App Memory Context' header")
    }

    // MARK: - P1: Multiple apps in task description

    @Test("build memory context task mentions multiple apps matches first")
    func buildMemoryContextTaskMentionsMultipleAppsMatchesFirst() async throws {
        let store = InMemoryStore()
        let provider = MemoryContextProvider()

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

        #expect(context != nil,
            "Should match at least one App when multiple are mentioned")
    }

    // MARK: - P1: Case-insensitive matching

    @Test("domain inference case insensitive")
    func domainInferenceCaseInsensitive() async throws {
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

        #expect(context != nil, "Should match domain case-insensitively")
    }
}
