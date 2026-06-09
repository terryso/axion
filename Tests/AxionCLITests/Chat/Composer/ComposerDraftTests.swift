import Testing
@testable import AxionCLI

@Suite("ComposerDraft")
struct ComposerDraftTests {

    @Test("snapshot 保存 text 和 cursor")
    func snapshotSavesTextAndCursor() {
        let draft = ComposerDraft.snapshot(text: "hello", cursor: 5)
        #expect(draft.text == "hello")
        #expect(draft.cursor == 5)
    }

    @Test("restore 返回正确的 text 和 cursor")
    func restoreReturnsCorrectValues() {
        let draft = ComposerDraft.snapshot(text: "你好", cursor: 1)
        let restored = draft.restore()
        #expect(restored.text == "你好")
        #expect(restored.cursor == 1)
    }

    @Test("Equatable — 相同值相等")
    func equatableSame() {
        let a = ComposerDraft(text: "test", cursor: 2)
        let b = ComposerDraft(text: "test", cursor: 2)
        #expect(a == b)
    }

    @Test("Equatable — 不同值不等")
    func equatableDifferent() {
        let a = ComposerDraft(text: "test", cursor: 2)
        let b = ComposerDraft(text: "test", cursor: 3)
        #expect(a != b)
    }

    @Test("空 text 快照")
    func emptySnapshot() {
        let draft = ComposerDraft.snapshot(text: "", cursor: 0)
        #expect(draft.text.isEmpty)
        #expect(draft.cursor == 0)
    }
}
