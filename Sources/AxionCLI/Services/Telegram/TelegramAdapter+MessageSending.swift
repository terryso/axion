extension TelegramAdapter {

    // MARK: - Formatted Message Sending

    @discardableResult
    func sendFormatted(_ text: String, to chatId: Int64, replyToMessageId: Int64? = nil) async -> Int64? {
        let preferredPayload = preferredFormattedPayload(for: text)
        let mode = preferredPayload.parseMode
        let chunks = preferredPayload.chunks

        var sentCount = 0
        var firstMessageId: Int64?
        for (index, chunk) in chunks.enumerated() {
            let replyId = index == 0 ? replyToMessageId : nil

            do {
                let msg = try await apiClient.sendMessage(chatId: chatId, text: chunk, parseMode: mode, replyToMessageId: replyId)
                if firstMessageId == nil { firstMessageId = msg.messageId }
                sentCount += 1
            } catch let error as TGAPIError {
                switch error {
                case .formatRejected:
                    await sendFallbackChunks(
                        text: text,
                        to: chatId,
                        replyToMessageId: replyToMessageId,
                        startIndex: sentCount,
                        failedMode: mode
                    )
                    return firstMessageId
                default:
                    log("[axion] Telegram sendFormatted failed: \(error.localizedDescription)")
                }
            } catch {
                log("[axion] Telegram sendFormatted failed: \(error.localizedDescription)")
            }
        }
        return firstMessageId
    }

    // MARK: - Payload Selection

    private func preferredFormattedPayload(for text: String) -> TGFormattedPayload {
        let (markdownText, markdownMode) = TGMessageFormatter.format(text)
        let markdownChunks = TGMessageFormatter.split(formattedText: markdownText, parseMode: markdownMode)
        let markdownPayload = TGFormattedPayload(
            formattedText: markdownText,
            parseMode: markdownMode,
            chunks: markdownChunks
        )

        let (htmlText, htmlMode) = TGMessageFormatter.formatAsHTML(text)
        let htmlChunks = TGMessageFormatter.split(formattedText: htmlText, parseMode: htmlMode)
        let htmlPayload = TGFormattedPayload(
            formattedText: htmlText,
            parseMode: htmlMode,
            chunks: htmlChunks
        )

        if htmlPayload.chunks.count < markdownPayload.chunks.count {
            return htmlPayload
        }

        return markdownPayload
    }

    // MARK: - Fallback Chains

    private func sendFallbackChunks(
        text: String,
        to chatId: Int64,
        replyToMessageId: Int64?,
        startIndex: Int,
        failedMode: TGParseMode
    ) async {
        if failedMode == .markdownV2 {
            await sendHTMLFallbackChunks(text: text, to: chatId, replyToMessageId: replyToMessageId, startIndex: startIndex)
            return
        }

        await sendPlainFallbackChunks(text: text, to: chatId, replyToMessageId: replyToMessageId, startIndex: startIndex)
    }

    private func sendHTMLFallbackChunks(text: String, to chatId: Int64, replyToMessageId: Int64?, startIndex: Int) async {
        let (htmlFormatted, htmlMode) = TGMessageFormatter.formatAsHTML(text)
        let htmlChunks = TGMessageFormatter.split(formattedText: htmlFormatted, parseMode: htmlMode)

        for (hIndex, htmlChunk) in htmlChunks.enumerated() {
            guard hIndex >= startIndex else { continue }
            let hReplyId = hIndex == 0 ? replyToMessageId : nil
            do {
                _ = try await apiClient.sendMessage(chatId: chatId, text: htmlChunk, parseMode: htmlMode, replyToMessageId: hReplyId)
            } catch {
                await sendPlainFallbackChunks(text: text, to: chatId, replyToMessageId: replyToMessageId, startIndex: startIndex)
                return
            }
        }
    }

    private func sendPlainFallbackChunks(text: String, to chatId: Int64, replyToMessageId: Int64?, startIndex: Int) async {
        let (plainFormatted, plainMode) = TGMessageFormatter.formatAsPlain(text)
        let plainChunks = TGMessageFormatter.split(formattedText: plainFormatted, parseMode: plainMode)

        for (pIndex, plainChunk) in plainChunks.enumerated() {
            guard pIndex >= startIndex else { continue }
            let pReplyId = pIndex == 0 ? replyToMessageId : nil
            do {
                _ = try await apiClient.sendMessage(chatId: chatId, text: plainChunk, parseMode: plainMode, replyToMessageId: pReplyId)
            } catch {
                log("[axion] Telegram sendFormatted plain fallback failed: \(error.localizedDescription)")
            }
        }
    }
}
