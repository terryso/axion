import Testing
@testable import AxionCLI

@Suite("ChatComposer slash popup paging")
struct ChatComposerSlashPopupPagingTests {
    @Test("P0: Down beyond first popup page and Enter submits selected absolute item")
    func downBeyondFirstPageEnterSubmitsAbsoluteSelection() {
        let skills = (1...60).map { index in
            SkillInfo(name: "skill-\(index)", description: "Skill \(index)", aliases: [])
        }
        let expectedItems = SlashPopup.filter(query: "/", skills: skills)
        let expected = expectedItems[20].kind.displayName
        let capture = OutputCapture()
        let reader = MockKeyReader(
            [.printable("/")] + Array(repeating: KeyEvent.down, count: 20) + [.enter]
        )
        var composer = ChatComposer(
            isTTY: true,
            writeStdout: { capture.stdout += $0 },
            writeStderr: { capture.stderr += $0 },
            readLineFn: { nil },
            keyReader: reader
        )
        composer.availableSkills = skills

        let result = composer.readInput(prompt: "> ", continuationPrompt: "...> ")

        #expect(result == expected)
        #expect(capture.stdout.contains("21."))
        #expect(capture.stdout.contains(expected))
    }
}
