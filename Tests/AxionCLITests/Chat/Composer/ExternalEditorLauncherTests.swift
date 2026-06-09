import Testing
@testable import AxionCLI

@Suite("ExternalEditorLauncher")
struct ExternalEditorLauncherTests {

    // MARK: - resolveEditor

    @Test("VISUAL 优先于 EDITOR")
    func visualOverEditor() {
        let launcher = ExternalEditorLauncher(
            envVar: { key in key == "VISUAL" ? "vim" : (key == "EDITOR" ? "nano" : nil) },
            createTempFile: { _ in nil },
            readFile: { _ in nil },
            deleteFile: { _ in },
            launchProcess: { _, _ in nil },
            restoreTerminal: { },
            reEnterRawMode: { }
        )
        #expect(launcher.resolveEditor() == "vim")
    }

    @Test("EDITOR 回退")
    func editorFallback() {
        let launcher = ExternalEditorLauncher(
            envVar: { key in key == "EDITOR" ? "nano" : nil },
            createTempFile: { _ in nil },
            readFile: { _ in nil },
            deleteFile: { _ in },
            launchProcess: { _, _ in nil },
            restoreTerminal: { },
            reEnterRawMode: { }
        )
        #expect(launcher.resolveEditor() == "nano")
    }

    @Test("均未设置 → 返回 nil")
    func noEditorSet() {
        let launcher = ExternalEditorLauncher(
            envVar: { _ in nil },
            createTempFile: { _ in nil },
            readFile: { _ in nil },
            deleteFile: { _ in },
            launchProcess: { _, _ in nil },
            restoreTerminal: { },
            reEnterRawMode: { }
        )
        #expect(launcher.resolveEditor() == nil)
    }

    @Test("VISUAL 为空字符串 → 回退到 EDITOR")
    func emptyVisual() {
        let launcher = ExternalEditorLauncher(
            envVar: { key in key == "VISUAL" ? "" : (key == "EDITOR" ? "nano" : nil) },
            createTempFile: { _ in nil },
            readFile: { _ in nil },
            deleteFile: { _ in },
            launchProcess: { _, _ in nil },
            restoreTerminal: { },
            reEnterRawMode: { }
        )
        #expect(launcher.resolveEditor() == "nano")
    }

    // MARK: - launch

    @Test("编辑器正常退出 → 返回编辑内容")
    func launchSuccess() {
        var deletedPath: String?
        let launcher = ExternalEditorLauncher(
            envVar: { _ in "vim" },
            createTempFile: { content in
                #expect(content == "initial")
                return "/tmp/test-file.md"
            },
            readFile: { path in
                #expect(path == "/tmp/test-file.md")
                return "edited content"
            },
            deleteFile: { path in deletedPath = path },
            launchProcess: { _, args in
                #expect(args == ["/tmp/test-file.md"])
                return 0
            },
            restoreTerminal: { },
            reEnterRawMode: { }
        )

        let result = launcher.launch(editor: "vim", initialContent: "initial")
        #expect(result == "edited content")
        #expect(deletedPath == "/tmp/test-file.md")
    }

    @Test("编辑器非零退出 → 返回 nil")
    func launchNonZeroExit() {
        let launcher = ExternalEditorLauncher(
            envVar: { _ in "vim" },
            createTempFile: { _ in "/tmp/test-file.md" },
            readFile: { _ in "should not read" },
            deleteFile: { _ in },
            launchProcess: { _, _ in 1 },
            restoreTerminal: { },
            reEnterRawMode: { }
        )

        let result = launcher.launch(editor: "vim", initialContent: "initial")
        #expect(result == nil)
    }

    @Test("临时文件创建失败 → 返回 nil")
    func tempFileCreationFails() {
        var restoreCalled = false
        var reEnterCalled = false
        let launcher = ExternalEditorLauncher(
            envVar: { _ in "vim" },
            createTempFile: { _ in nil },  // 模拟创建失败
            readFile: { _ in nil },
            deleteFile: { _ in },
            launchProcess: { _, _ in 0 },
            restoreTerminal: { restoreCalled = true },
            reEnterRawMode: { reEnterCalled = true }
        )

        let result = launcher.launch(editor: "vim", initialContent: "initial")
        #expect(result == nil)
        // 临时文件创建失败不应调用 restore/reEnter
        #expect(!restoreCalled)
        #expect(!reEnterCalled)
    }

    @Test("进程启动失败 → 返回 nil")
    func processLaunchFails() {
        var restoreCalled = false
        var reEnterCalled = false
        let launcher = ExternalEditorLauncher(
            envVar: { _ in "vim" },
            createTempFile: { _ in "/tmp/test-file.md" },
            readFile: { _ in nil },
            deleteFile: { _ in },
            launchProcess: { _, _ in nil },  // 模拟启动失败
            restoreTerminal: { restoreCalled = true },
            reEnterRawMode: { reEnterCalled = true }
        )

        let result = launcher.launch(editor: "vim", initialContent: "initial")
        #expect(result == nil)
        // 即使启动失败也应恢复终端
        #expect(restoreCalled)
        #expect(reEnterCalled)
    }
}
