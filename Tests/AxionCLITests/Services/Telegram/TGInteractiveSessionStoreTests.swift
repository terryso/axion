import Testing
import Foundation
@testable import AxionCLI

@Suite("TGInteractiveSessionStore")
struct TGInteractiveSessionStoreTests {

    // MARK: - TGCallbackData

    @Test("TGCallbackData encodes action:detail:pendingId")
    func callbackDataEncoding() {
        let data = TGCallbackData(action: .approve, detail: "once", pendingId: "run-abc")
        #expect(data.encoded == "approve:once:run-abc")
    }

    @Test("TGCallbackData encodes with empty detail as action::pendingId")
    func callbackDataEncodingEmptyDetail() {
        let data = TGCallbackData(action: .deny, pendingId: "run-abc")
        #expect(data.encoded == "deny::run-abc")
    }

    @Test("TGCallbackData decodes 3-part format")
    func callbackDataDecoding3Part() {
        let data = TGCallbackData(rawValue: "deny:once:run-xyz")
        #expect(data != nil)
        #expect(data?.action == .deny)
        #expect(data?.detail == "once")
        #expect(data?.pendingId == "run-xyz")
    }

    @Test("TGCallbackData decodes 2-part format (backward compat)")
    func callbackDataDecoding2Part() {
        let data = TGCallbackData(rawValue: "deny:run-xyz")
        #expect(data != nil)
        #expect(data?.action == .deny)
        #expect(data?.detail == "")
        #expect(data?.pendingId == "run-xyz")
    }

    @Test("TGCallbackData returns nil for invalid format")
    func callbackDataInvalid() {
        #expect(TGCallbackData(rawValue: "invalid") == nil)
        #expect(TGCallbackData(rawValue: "") == nil)
        #expect(TGCallbackData(rawValue: "bogus:nope") == nil)
    }

    @Test("All TGCallbackAction raw values")
    func callbackActionRawValues() {
        #expect(TGCallbackAction.approve.rawValue == "approve")
        #expect(TGCallbackAction.deny.rawValue == "deny")
        #expect(TGCallbackAction.confirm.rawValue == "ok")
        #expect(TGCallbackAction.cancel.rawValue == "cancel")
        #expect(TGCallbackAction.skip.rawValue == "skip")
        #expect(TGCallbackAction.respond.rawValue == "respond")
        #expect(TGCallbackAction.clarify.rawValue == "clarify")
    }

    // MARK: - Register & Resume

    @Test("Register and resume session")
    func registerAndResume() async throws {
        let store = TGInteractiveSessionStore()
        let capture = ResumeCapture()
        let handler: @Sendable (String) async throws -> Void = { response in
            await capture.record(response)
        }

        await store.register(
            pendingId: "p1",
            chatId: 123,
            messageId: 42,
            mode: .approval,
            allowedUserId: 123,
            onResume: handler
        )

        let result = try await store.resume(pendingId: "p1", response: "approved")
        #expect(result == true)
        let resumedWith = await capture.value
        #expect(resumedWith == "approved")

        // Session removed after resume
        let session = await store.get(pendingId: "p1")
        #expect(session == nil)
    }

    @Test("Resume unknown session returns false")
    func resumeUnknown() async throws {
        let store = TGInteractiveSessionStore()
        let result = try await store.resume(pendingId: "unknown", response: "x")
        #expect(result == false)
    }

    @Test("Resume expired session returns false")
    func resumeExpired() async throws {
        let store = TGInteractiveSessionStore()
        let handler: @Sendable (String) async throws -> Void = { _ in }
        await store.register(
            pendingId: "p2",
            chatId: 123,
            messageId: 1,
            mode: .confirm,
            allowedUserId: 123,
            ttlSeconds: 0,
            onResume: handler
        )

        // Give a tiny delay so time passes
        try await _Concurrency.Task.sleep(nanoseconds: 10_000_000)

        let result = try await store.resume(pendingId: "p2", response: "ok")
        #expect(result == false)
    }

    // MARK: - Remove

    @Test("Remove returns session and deletes it")
    func removeSession() async {
        let store = TGInteractiveSessionStore()
        let handler: @Sendable (String) async throws -> Void = { _ in }
        await store.register(pendingId: "p3", chatId: 123, messageId: 1, mode: .clarify, allowedUserId: 123, onResume: handler)

        let removed = await store.remove(pendingId: "p3")
        #expect(removed != nil)
        #expect(removed?.pendingId == "p3")

        let gone = await store.get(pendingId: "p3")
        #expect(gone == nil)
    }

    // MARK: - session(for chatId)

    @Test("session(for:) finds active session by chatId")
    func sessionForChatId() async {
        let store = TGInteractiveSessionStore()
        let handler: @Sendable (String) async throws -> Void = { _ in }
        await store.register(pendingId: "p4", chatId: 999, messageId: 1, mode: .approval, allowedUserId: 999, onResume: handler)

        let session = await store.session(for: 999)
        #expect(session != nil)
        #expect(session?.pendingId == "p4")
    }

    @Test("session(for:) returns nil for unknown chatId")
    func sessionForUnknownChatId() async {
        let store = TGInteractiveSessionStore()
        let session = await store.session(for: 888)
        #expect(session == nil)
    }

    // MARK: - activeSessionCount

    @Test("activeSessionCount tracks registered sessions")
    func activeSessionCount() async {
        let store = TGInteractiveSessionStore()
        #expect(await store.activeSessionCount == 0)

        let handler: @Sendable (String) async throws -> Void = { _ in }
        await store.register(pendingId: "a", chatId: 1, messageId: 1, mode: .approval, allowedUserId: 1, onResume: handler)
        #expect(await store.activeSessionCount == 1)

        await store.register(pendingId: "b", chatId: 2, messageId: 1, mode: .confirm, allowedUserId: 2, onResume: handler)
        #expect(await store.activeSessionCount == 2)

        _ = await store.remove(pendingId: "a")
        #expect(await store.activeSessionCount == 1)
    }

    // MARK: - Keyboard Building

    @Test("Approval keyboard has Allow Once, Session, Always + Deny buttons")
    func approvalKeyboard() async {
        let store = TGInteractiveSessionStore()
        let kb = await store.buildKeyboard(for: .approval, pendingId: "p1")
        #expect(kb.inlineKeyboard.count == 2)
        // Row 1: Allow Once, Session, Always
        #expect(kb.inlineKeyboard[0].count == 3)
        #expect(kb.inlineKeyboard[0][0].text == "Allow Once")
        #expect(kb.inlineKeyboard[0][0].callbackData == "approve:once:p1")
        #expect(kb.inlineKeyboard[0][1].text == "Session")
        #expect(kb.inlineKeyboard[0][1].callbackData == "approve:session:p1")
        #expect(kb.inlineKeyboard[0][2].text == "Always")
        #expect(kb.inlineKeyboard[0][2].callbackData == "approve:always:p1")
        // Row 2: Deny
        #expect(kb.inlineKeyboard[1].count == 1)
        #expect(kb.inlineKeyboard[1][0].text == "Deny")
        #expect(kb.inlineKeyboard[1][0].callbackData == "deny::p1")
    }

    @Test("Confirm keyboard has Approve Once, Always Approve + Cancel buttons")
    func confirmKeyboard() async {
        let store = TGInteractiveSessionStore()
        let kb = await store.buildKeyboard(for: .confirm, pendingId: "p2")
        #expect(kb.inlineKeyboard.count == 2)
        // Row 1: Approve Once, Always Approve
        #expect(kb.inlineKeyboard[0].count == 2)
        #expect(kb.inlineKeyboard[0][0].text == "Approve Once")
        #expect(kb.inlineKeyboard[0][0].callbackData == "ok:once:p2")
        #expect(kb.inlineKeyboard[0][1].text == "Always Approve")
        #expect(kb.inlineKeyboard[0][1].callbackData == "ok:always:p2")
        // Row 2: Cancel
        #expect(kb.inlineKeyboard[1].count == 1)
        #expect(kb.inlineKeyboard[1][0].text == "Cancel")
        #expect(kb.inlineKeyboard[1][0].callbackData == "cancel::p2")
    }

    @Test("Clarify keyboard shows individual options + Type Answer")
    func clarifyKeyboard() async {
        let store = TGInteractiveSessionStore()
        let options = ["Option A", "Option B", "Option C"]
        let kb = await store.buildKeyboard(for: .clarify, pendingId: "p3", clarifyOptions: options)
        // 3 option rows + 1 Type Answer row
        #expect(kb.inlineKeyboard.count == 4)
        // Each option button
        #expect(kb.inlineKeyboard[0][0].text == "Option A")
        #expect(kb.inlineKeyboard[0][0].callbackData == "clarify:0:p3")
        #expect(kb.inlineKeyboard[1][0].text == "Option B")
        #expect(kb.inlineKeyboard[1][0].callbackData == "clarify:1:p3")
        #expect(kb.inlineKeyboard[2][0].text == "Option C")
        #expect(kb.inlineKeyboard[2][0].callbackData == "clarify:2:p3")
        // Type Answer row
        #expect(kb.inlineKeyboard[3][0].text == "Type Answer")
        #expect(kb.inlineKeyboard[3][0].callbackData == "respond::p3")
    }

    @Test("TextCapture keyboard has only Skip button")
    func textCaptureKeyboard() async {
        let store = TGInteractiveSessionStore()
        let kb = await store.buildKeyboard(for: .textCapture, pendingId: "p4")
        #expect(kb.inlineKeyboard.count == 1)
        #expect(kb.inlineKeyboard[0].count == 1)
        #expect(kb.inlineKeyboard[0][0].text == "Skip")
    }

    @Test("Callback data stays under 64 bytes")
    func callbackDataSizeLimit() async {
        let store = TGInteractiveSessionStore()
        let longId = String(repeating: "x", count: 40)
        let kb = await store.buildKeyboard(for: .approval, pendingId: longId)
        for row in kb.inlineKeyboard {
            for button in row {
                if let data = button.callbackData {
                    #expect(data.utf8.count <= 64, "callback_data '\(data)' exceeds 64 bytes")
                }
            }
        }
    }

    // MARK: - clarifyOptions stored in session

    @Test("Session stores clarifyOptions")
    func clarifyOptionsStored() async {
        let store = TGInteractiveSessionStore()
        let handler: @Sendable (String) async throws -> Void = { _ in }
        let options = ["Red", "Blue"]
        await store.register(
            pendingId: "p5",
            chatId: 100,
            messageId: 1,
            mode: .clarify,
            clarifyOptions: options,
            allowedUserId: 100,
            onResume: handler
        )
        let session = await store.get(pendingId: "p5")
        #expect(session?.clarifyOptions == ["Red", "Blue"])
    }

    @Test("Session stores allowedUserId")
    func allowedUserIdStored() async {
        let store = TGInteractiveSessionStore()
        let handler: @Sendable (String) async throws -> Void = { _ in }
        await store.register(
            pendingId: "p6",
            chatId: 100,
            messageId: 1,
            mode: .approval,
            allowedUserId: 42,
            onResume: handler
        )
        let session = await store.get(pendingId: "p6")
        #expect(session?.allowedUserId == 42)
    }
}

/// Thread-safe capture for resume handler results in tests.
private actor ResumeCapture {
    private var _value: String?
    var value: String? { _value }
    func record(_ v: String) { _value = v }
}
