import Testing
@testable import AxionCLI

@Suite("ComposerMode")
struct ComposerModeTests {

    @Test("normal 模式 isNormal 为 true")
    func normalIsNormal() {
        let mode = ComposerMode.normal
        #expect(mode.isNormal)
    }

    @Test("slashPopup 模式 isNormal 为 false")
    func slashPopupNotNormal() {
        let mode = ComposerMode.slashPopup(query: "/help")
        #expect(!mode.isNormal)
    }

    @Test("historySearch 模式 isNormal 为 false")
    func historySearchNotNormal() {
        let mode = ComposerMode.historySearch(query: "test")
        #expect(!mode.isNormal)
    }

    @Test("fileSearch 模式 isNormal 为 false")
    func fileSearchNotNormal() {
        let mode = ComposerMode.fileSearch(query: "src")
        #expect(!mode.isNormal)
    }

    @Test("approval 模式 isNormal 为 false")
    func approvalNotNormal() {
        let mode = ComposerMode.approval
        #expect(!mode.isNormal)
    }

    @Test("Equatable — 相同模式相等")
    func equatableSame() {
        #expect(ComposerMode.normal == ComposerMode.normal)
        #expect(ComposerMode.approval == ComposerMode.approval)
    }

    @Test("Equatable — 不同模式不等")
    func equatableDifferent() {
        #expect(ComposerMode.normal != ComposerMode.approval)
    }

    @Test("Equatable — 关联值相同相等")
    func equatableAssociatedSame() {
        #expect(
            ComposerMode.slashPopup(query: "/h") == ComposerMode.slashPopup(query: "/h")
        )
    }

    @Test("Equatable — 关联值不同不等")
    func equatableAssociatedDifferent() {
        #expect(
            ComposerMode.slashPopup(query: "/h") != ComposerMode.slashPopup(query: "/help")
        )
    }
}
