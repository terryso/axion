import Testing

@testable import AxionCLI

// MARK: - AC3/AC4: SessionAllowList 测试

@Suite("SessionAllowList")
struct SessionAllowListTests {

    // MARK: - 精确匹配 (AC3)

    @Test("空列表不匹配任何命令")
    func emptyListNoMatch() {
        let list = SessionAllowList()
        #expect(!list.isAllowed(command: "git commit"))
        #expect(!list.isAllowed(command: "swift test"))
    }

    @Test("精确匹配: add → isAllowed")
    func exactMatch() {
        var list = SessionAllowList()
        list.addExact("swift test")
        #expect(list.isAllowed(command: "swift test"))
        #expect(!list.isAllowed(command: "swift build"))
    }

    @Test("精确匹配区分不同命令")
    func exactMatchDifferentCommands() {
        var list = SessionAllowList()
        list.addExact("git commit -m \"fix\"")
        #expect(list.isAllowed(command: "git commit -m \"fix\""))
        #expect(!list.isAllowed(command: "git commit -m \"docs\""))
    }

    @Test("多个精确匹配")
    func multipleExactMatches() {
        var list = SessionAllowList()
        list.addExact("swift test")
        list.addExact("swift build")
        list.addExact("git status")
        #expect(list.isAllowed(command: "swift test"))
        #expect(list.isAllowed(command: "swift build"))
        #expect(list.isAllowed(command: "git status"))
        #expect(!list.isAllowed(command: "swift run"))
    }

    @Test("重复 addExact 不创建重复条目（Set 语义）")
    func duplicateAddExact() {
        var list = SessionAllowList()
        list.addExact("swift test")
        list.addExact("swift test")
        #expect(list.exactMatches.count == 1)
    }

    // MARK: - 前缀匹配 (AC4)

    @Test("前缀匹配: git commit -m \"msg\" 注册后匹配同前缀命令")
    func prefixMatch() {
        var list = SessionAllowList()
        list.addPrefix(for: "git commit -m \"fix: bug\"")
        #expect(list.isAllowed(command: "git commit -m \"docs: update\""))
        #expect(list.isAllowed(command: "git commit -m \"feat: new\""))
    }

    @Test("前缀不误匹配: git commit 规则不匹配 git push")
    func prefixNoFalsePositive() {
        var list = SessionAllowList()
        list.addPrefix(for: "git commit -m \"fix\"")
        #expect(!list.isAllowed(command: "git push origin main"))
        #expect(!list.isAllowed(command: "git log"))
    }

    @Test("前缀规则至少 2 tokens")
    func prefixMinTwoTokens() {
        var list = SessionAllowList()
        // 单 token "make" → 退化为精确匹配
        list.addPrefix(for: "make")
        #expect(list.exactMatches.contains("make"))
        #expect(list.prefixRules.isEmpty)
    }

    @Test("两 token 命令正确注册前缀规则")
    func twoTokenPrefix() {
        var list = SessionAllowList()
        list.addPrefix(for: "swift build")
        // 匹配 swift build + 任意后缀
        #expect(list.isAllowed(command: "swift build"))
        #expect(list.isAllowed(command: "swift build --configuration release"))
        // 不匹配 swift test
        #expect(!list.isAllowed(command: "swift test"))
    }

    @Test("前缀规则不重复注册")
    func noDuplicatePrefixRules() {
        var list = SessionAllowList()
        list.addPrefix(for: "git commit -m \"fix\"")
        list.addPrefix(for: "git commit -m \"docs\"")
        // 相同前缀 tokens ["git", "commit"] 只注册一次
        #expect(list.prefixRules.count == 1)
    }

    // MARK: - 前缀预览 (AC4)

    @Test("prefixPreview 返回正确格式")
    func prefixPreview() {
        let list = SessionAllowList()
        #expect(list.prefixPreview(for: "git commit -m \"fix\"") == "git commit*")
        #expect(list.prefixPreview(for: "swift build") == "swift build*")
        #expect(list.prefixPreview(for: "make") == "make*")
    }

    // MARK: - 精确匹配优先于前缀匹配

    @Test("精确匹配优先于前缀匹配")
    func exactMatchBeforePrefix() {
        var list = SessionAllowList()
        list.addPrefix(for: "git commit -m \"fix\"")
        list.addExact("git push origin main")
        // 精确匹配
        #expect(list.isAllowed(command: "git push origin main"))
        // 前缀匹配
        #expect(list.isAllowed(command: "git commit -m \"docs\""))
        // 不匹配
        #expect(!list.isAllowed(command: "git log"))
    }

    // MARK: - SessionAllowListRef 测试

    @Test("SessionAllowListRef 正确代理调用")
    func refProxyCalls() {
        let ref = SessionAllowListRef()
        #expect(!ref.isAllowed(command: "swift test"))

        ref.addExact("swift test")
        #expect(ref.isAllowed(command: "swift test"))

        ref.addPrefix(for: "git commit -m \"fix\"")
        #expect(ref.isAllowed(command: "git commit -m \"docs\""))
        #expect(!ref.isAllowed(command: "git push"))
    }

    @Test("SessionAllowListRef prefixPreview 正确")
    func refPrefixPreview() {
        let ref = SessionAllowListRef()
        #expect(ref.prefixPreview(for: "git commit -m \"fix\"") == "git commit*")
    }

    @Test("SessionAllowListRef 共享状态")
    func refSharedState() {
        let ref = SessionAllowListRef()
        ref.addExact("swift build")
        // list 属性返回快照，应包含已添加的条目
        #expect(ref.list.exactMatches.contains("swift build"))
    }
}
