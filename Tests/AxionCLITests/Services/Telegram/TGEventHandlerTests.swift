import Testing
import Foundation
import OpenAgentSDK
import AxionCore

@testable import AxionCLI

@Suite("TGEventHandler")
struct TGEventHandlerTests {
    /// Collects (message, chatId) pairs sent via the sendMessage closure.
    private final class MessageCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var _messages: [(message: String, chatId: Int64)] = []

        var messages: [(message: String, chatId: Int64)] {
            lock.lock()
            defer { lock.unlock() }
            return _messages
        }

        func append(_ message: String, chatId: Int64) {
            lock.lock()
            _messages.append((message, chatId))
            lock.unlock()
        }

        func clear() {
            lock.lock()
            _messages.removeAll()
            lock.unlock()
        }
    }

    private func makeContext() -> EventHandlerContext {
        EventHandlerContext(
            sessionId: "test-session",
            config: .default,
            eventBus: nil,
            externallyModified: false,
            externallyModifiedFlag: nil,
            takeoverEvent: nil,
            runCompleteContext: nil,
            sessionStore: SessionStore(sessionsDir: "/tmp/axion-test-sessions")
        )
    }

    private func makeHandler(
        chatId: Int64 = 123,
        collector: MessageCollector
    ) -> TGEventHandler {
        TGEventHandler(chatId: chatId, sendMessage: { message, chatId in
            collector.append(message, chatId: chatId)
            return nil
        })
    }

    // MARK: - Subscribed event types (streaming + non-streaming)

    @Test("Subscribes to correct event types including streaming")
    func subscribedEventTypes() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)

        let types = await handler.subscribedEventTypes.map { $0 }
        let typeNames = Set(types.map { String(describing: $0) })

        #expect(typeNames.contains("LLMTokenStreamEvent"))
        #expect(typeNames.contains("ToolStartedEvent"))
        #expect(typeNames.contains("ToolStreamingEvent"))
        #expect(typeNames.contains("ToolCompletedEvent"))
        #expect(typeNames.contains("AgentCompletedEvent"))
        #expect(typeNames.contains("AgentFailedEvent"))
        #expect(typeNames.contains("ReviewResultEvent"))
        #expect(typeNames.contains("AgentPausedEvent"))
        #expect(types.count == 8)
    }

    // MARK: - extractLastResultSection

    @Test("extractLastResultSection returns full text when no [结果] marker")
    func extractResultNoMarker() {
        let text = "Task completed successfully."
        #expect(TGEventHandler.extractLastResultSection(from: text) == text)
    }

    @Test("extractLastResultSection returns full text when single [结果] marker")
    func extractResultSingleMarker() {
        let text = "Some work done.\n[结果] Task completed."
        #expect(TGEventHandler.extractLastResultSection(from: text) == text)
    }

    @Test("extractLastResultSection trims stale observations from previous session task")
    func extractResultTrimsStaleSection() {
        let text = """
        计算器已经打开了，看起来之前输入过 5+3，显示 8。
        ✅ 计算结果：5 + 3 = 8
        [结果] 计算器已打开，5+3=8 计算完成

        先清除之前的计算，然后点击 5、+、9、8、=
        ✅ 计算完成：5 + 98 = 103
        从计算器确认：5+98=103
        [结果] 计算器已计算 5+98=103
        """
        let result = TGEventHandler.extractLastResultSection(from: text)
        #expect(!result.contains("5+3=8"))
        #expect(!result.contains("计算器已经打开了"))
        #expect(result.contains("5+98=103"))
        #expect(result.contains("[结果] 计算器已计算 5+98=103"))
    }

    // MARK: - AgentFailedEvent pushes error (no API key)

    @Test("AgentFailedEvent pushes error message without API key")
    func agentFailedPushesError() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = AgentFailedEvent(
            sessionId: nil,
            error: "Connection timeout",
            stepsCompleted: 3
        )
        await handler.handle(event, context: context)

        let messages = collector.messages
        #expect(messages.count == 1)
        #expect(messages[0].message.contains("任务失败"))
        // Error sanitizer maps timeout to Chinese
        #expect(messages[0].message.contains("命令执行超时"))
    }

    @Test("AgentFailedEvent sanitizes API keys from error")
    func agentFailedSanitizesKeys() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = AgentFailedEvent(
            sessionId: nil,
            error: "Invalid key sk-abc123def456ghi789jkl012mno345 in request",
            stepsCompleted: 1
        )
        await handler.handle(event, context: context)

        let messages = collector.messages
        #expect(messages.count == 1)
        #expect(!messages[0].message.contains("sk-abc123"))
        #expect(messages[0].message.contains("[REDACTED_KEY]"))
    }

    @Test("AgentFailedEvent sanitizes file paths from error")
    func agentFailedSanitizesPaths() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = AgentFailedEvent(
            sessionId: nil,
            error: "Error reading /Users/nick/.config/axion/secrets.json",
            stepsCompleted: 1
        )
        await handler.handle(event, context: context)

        let messages = collector.messages
        #expect(messages.count == 1)
        #expect(!messages[0].message.contains("Users/nick"))
        #expect(messages[0].message.contains("secrets.json"))
    }

    // MARK: - Streaming delegation: ToolCompletedEvent no longer sends step message

    @Test("ToolCompletedEvent does not send a direct Telegram message")
    func toolCompletedDoesNotPushDirectMessage() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = ToolCompletedEvent(
            sessionId: nil,
            toolUseId: "tu-1",
            toolName: "screenshot",
            durationMs: 230,
            isError: false
        )
        await handler.handle(event, context: context)

        let messages = collector.messages
        #expect(messages.isEmpty)
    }

    // MARK: - ReviewResultEvent handling

    @Test("ReviewResultEvent with changes pushes review summary")
    func reviewResultWithChangesPushes() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = ReviewResultEvent(
            summary: "review done",
            memoryChanges: ["mem-1", "mem-2"],
            skillChanges: ["skill-1"],
            success: true,
            durationMs: 500,
            sessionId: "s-1"
        )
        await handler.handle(event, context: context)

        #expect(collector.messages.count == 1)
        #expect(collector.messages[0].message.contains("审查完成"))
        #expect(collector.messages[0].message.contains("2 条记忆"))
        #expect(collector.messages[0].message.contains("1 个技能"))
    }

    @Test("ReviewResultEvent failure pushes warning message")
    func reviewResultFailurePushesWarning() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = ReviewResultEvent(
            summary: "failed",
            memoryChanges: [],
            skillChanges: [],
            success: false,
            durationMs: 100,
            sessionId: "s-fail"
        )
        await handler.handle(event, context: context)

        #expect(collector.messages.count == 1)
        #expect(collector.messages[0].message.contains("审查失败"))
    }

    @Test("ReviewResultEvent success with no changes does not push")
    func reviewResultSuccessNoChangesNoPush() async {
        let collector = MessageCollector()
        let handler = makeHandler(collector: collector)
        let context = makeContext()

        let event = ReviewResultEvent(
            summary: "nothing to change",
            memoryChanges: [],
            skillChanges: [],
            success: true,
            durationMs: 50,
            sessionId: "s-noop"
        )
        await handler.handle(event, context: context)

        #expect(collector.messages.isEmpty)
    }

    // MARK: - stripMCPRawIO

    @Test("stripMCPRawIO extracts answer after last MCP block")
    func stripMCPRemovesToolIO() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com","return_format":"markdown"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"text": {"title": "Example"}}

        根据以上数据，答案是 42。

        [结果] 答案是 42
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("🌐"))
        #expect(!result.contains("Input:"))
        #expect(!result.contains("Output:"))
        #expect(!result.contains("webReader_result"))
        #expect(!result.contains("Built-in Tool"))
        #expect(result.contains("根据以上数据"))
        #expect(result.contains("[结果] 答案是 42"))
    }

    @Test("stripMCPRawIO handles multiple tool blocks with interleaved model text")
    func stripMCPHandlesMultipleBlocks() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://a.com"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"text": {"title": "A"}}

                                                数据似乎不太对。🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://b.com"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"text": {"title": "B"}}

                                                根据以上数据，最终答案如下。

        [结果] 最终答案
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("🌐"))
        #expect(!result.contains("webReader"))
        #expect(!result.contains("Built-in Tool"))
        #expect(result.contains("最终答案如下"))
        #expect(result.contains("[结果] 最终答案"))
    }

    @Test("stripMCPRawIO handles leading-whitespace tool blocks")
    func stripMCPHandlesIndentedBlocks() {
        let text = """
        some header
                                                🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com"}

        *Executing on server...*
                                                    Output:
        webReader_result_summary: {"text": {"title": "Example"}}

        根据以上数据，答案是 42。
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("🌐"))
        #expect(!result.contains("webReader"))
        #expect(!result.contains("Built-in Tool"))
        #expect(result.contains("some header"))
        #expect(result.contains("根据以上数据"))
    }

    @Test("stripMCPRawIO preserves text without tool blocks")
    func stripMCPPreservesPlain() {
        let text = "这是一段普通文本，没有任何工具输出。"
        #expect(TGEventHandler.stripMCPRawIO(from: text) == text)
    }

    @Test("stripMCPRawIO preserves text with Input: but no Output: (no MCP blocks)")
    func stripMCPFalsePositiveGuard() {
        let text = """
        让我解释一下。

        Input:
        这个字段接受 JSON 格式。

        没有对应的 Output 行，所以不应被当作 MCP 块删除。

        实际答案在这里。
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(result.contains("让我解释一下"))
        #expect(result.contains("Input:"))
        #expect(result.contains("实际答案在这里"))
    }

    @Test("stripMCPRawIO preserves literal Built-in Tool mention without MCP markers")
    func stripMCPLiteralHeaderGuard() {
        let text = """
        文档里提到了字符串 Built-in Tool: 作为调试说明。

        这里没有 Input 或 Output 块，所以不应被删除。
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(result == text)
    }

    @Test("stripMCPRawIO removes plain-text output payloads")
    func stripMCPRemovesPlainTextOutput() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com"}

        Output:
        Cached response from edge node
        March 2026 snapshot

        根据最新数据，明天不下雨。
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("Cached response"))
        #expect(!result.contains("March 2026 snapshot"))
        #expect(result.contains("根据最新数据"))
    }

    @Test("stripMCPRawIO handles pretty-printed multiline input")
    func stripMCPHandlesPrettyPrintedInput() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {
          "url": "https://example.com",
          "headers": {
            "accept": "text/html"
          },
          "options": {
            "format": "markdown",
            "cache": false
          }
        }

        Output:
        {"ok":true}

        [结果] 处理完成
        """
        let result = TGEventHandler.stripMCPRawIO(from: text)
        #expect(!result.contains("\"headers\""))
        #expect(!result.contains("\"cache\""))
        #expect(result.contains("[结果] 处理完成"))
    }

    // MARK: - cleanResultText

    @Test("cleanResultText strips MCP I/O and extracts result")
    func cleanResultTextStripsAndExtracts() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"text": {"title": "Example"}}

        根据以上数据，答案是 42。

        [结果] 答案是 42
        """
        let result = TGEventHandler.cleanResultText(from: text)
        #expect(!result.contains("🌐"))
        #expect(!result.contains("webReader"))
        #expect(result == "答案是 42")
        #expect(!result.contains("[结果]"))
    }

    @Test("cleanResultText strips weather-style interleaved MCP transcript")
    func cleanResultTextStripsWeatherTranscript() {
        let text = """
        我先帮你查一下广州明天的天气。
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://weather.example.com/guangzhou"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"forecast":"cloudy"}

        查询到了最新天气。🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://weather.example.com/guangzhou/advice"}

        *Executing on server...*

        Output:
        webReader_result_summary: {"advice":"carry umbrella"}

        广州明天多云，26°C 到 32°C，外出建议带伞。
        [结果] 广州明天多云，26°C 到 32°C，外出建议带伞。
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result == "广州明天多云，26°C 到 32°C，外出建议带伞。")
        #expect(!result.contains("Built-in Tool"))
        #expect(!result.contains("Input:"))
        #expect(!result.contains("Output:"))
        #expect(!result.contains("result_summary"))
        #expect(!result.contains("[结果]"))
    }

    @Test("cleanResultText prefers substantive prose over trailing result summary")
    func cleanResultTextPrefersSubstantiveProse() {
        let text = """
        已成功获取保利威最新 5 个频道：
        - 频道 A：直播中
        - 频道 B：等待中
        - 频道 C：等待中
        - 频道 D：未开始
        - 频道 E：未开始

        你可以继续告诉我要查看哪个频道的详细状态。

        [结果] 成功获取保利威最新5个频道，1个直播中，2个等待中，2个未开始
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result.contains("已成功获取保利威最新 5 个频道"))
        #expect(result.contains("频道 A：直播中"))
        #expect(result.contains("继续告诉我要查看哪个频道"))
        #expect(!result.contains("[结果]"))
        #expect(!result.hasPrefix("成功获取保利威最新5个频道"))
    }

    @Test("cleanResultText keeps introductory line for list-style answers")
    func cleanResultTextKeepsIntroLineForListAnswer() {
        let text = """
        成功获取最新5个频道信息：
        - 频道 A：直播中
        - 频道 B：等待中
        - 频道 C：等待中
        - 频道 D：未开始
        - 频道 E：未开始
        [结果] 成功获取最新5个频道信息，1个直播中，2个等待中，2个未开始
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result.hasPrefix("成功获取最新5个频道信息："))
        #expect(result.contains("频道 A：直播中"))
        #expect(!result.contains("[结果]"))
    }

    @Test("cleanResultText keeps trailing table and key points before result summary")
    func cleanResultTextKeepsTableAndKeyPoints() {
        let text = """
        认证状态正常，现在获取最新的5个频道信息：

        成功获取到最新的5个频道信息，以下是汇总：

        | # | 频道ID | 频道名称 | 状态 | 场景 | 模板 |
        |---|--------|---------|------|------|------|
        | 1 | 5762133 | 测试商品购买_te60dmiv | 🔴 直播中 (live) | topclass | portrait_alone |
        | 2 | 6099130 | 暖场图测试频道 | ⏳ 等待中 (waiting) | topclass | alone |

        **关键信息：**
        - 共5个频道，其中 **1个正在直播中**，2个处于等待状态，2个未开始
        - 所有频道场景均为 **topclass（大班课）**
        - 创建时间均为 2026-06-01
        - 当前使用的账号为默认账号 **nicksu**

        [结果] 成功获取5个频道信息，1个直播中、2个等待中、2个未开始
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result.contains("成功获取到最新的5个频道信息，以下是汇总："))
        #expect(result.contains("| # | 频道ID | 频道名称 | 状态 | 场景 | 模板 |"))
        #expect(result.contains("当前使用的账号为默认账号 **nicksu**"))
        #expect(!result.contains("认证状态正常，现在获取最新的5个频道信息："))
        #expect(!result.contains("[结果]"))
    }

    @Test("cleanResultText keeps rich weather answer when MCP blocks are markdown formatted")
    func cleanResultTextKeepsMarkdownFormattedWeatherAnswer() {
        let text = """
        **🌐 Z.ai Built-in Tool: webReader**

        **Input:**
        ```json
        {"url":"https://www.weather.com.cn/weather/101280101.shtml","return_format":"text","retain_images":false}
        ```

        *Executing on server...*

        **Output:**
        **webReader_result_summary:** [{"text": {"title": "广州天气预报", "content": "- 今天\\n- 7天"}}]

        以下是 **广州未来5天天气预报**（数据来源：中国天气网）：

        | 日期 | 天气 | 最高温 | 最低温 | 风力 |
        |------|------|--------|--------|------|
        | 📅 6月1日 | ⛅ 多云 | 35℃ | 27℃ | <3级 |
        | 📅 6月2日 | ⛅ 多云 | 35℃ | 27℃ | <3级 |
        | 📅 6月3日 | 🌩️ 雷阵雨转中雨 | 34℃ | 25℃ | <3级 |

        **总体趋势：**
        - 🌡️ **前两天持续高温闷热**，注意防暑降温
        - 🌧️ **第三天起迎来降雨**，气温小幅下降
        - 👕 穿衣建议：短衫、短裤等清凉夏季服装

        [结果] 已查询广州未来5天天气：前两天多云高温，第三天起雷阵雨降温
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result.contains("以下是 **广州未来5天天气预报**"))
        #expect(result.contains("| 日期 | 天气 | 最高温 | 最低温 | 风力 |"))
        #expect(result.contains("**总体趋势：**"))
        #expect(result.contains("第三天起迎来降雨"))
        #expect(!result.contains("Built-in Tool"))
        #expect(!result.contains("Input:"))
        #expect(!result.contains("Output:"))
        #expect(!result.contains("webReader_result_summary"))
        #expect(!result.contains("[结果]"))
        #expect(!result.hasPrefix("已查询广州未来5天天气"))
    }

    @Test("cleanResultText keeps full BMad status sections before trailing summary")
    func cleanResultTextKeepsBMadStatusSections() {
        let text = """
        ---

        ## 🎯 BMad Help — Axion Project Status

        ### Where You Are

        You're at a **major milestone** — **all 32 epics are marked `done`**.

        ### ✅ What's Complete

        | Phase | Description | Status |
        |-------|-------------|--------|
        | 1–3 | Core, Growth, Vision (Epics 1–11) | ✅ Done |
        | 12 | Telegram Experience Upgrades (Epic 32) | ✅ Done |

        ---

        ### 🔜 Recommended Next Steps

        **1. Commit your current work** — You have uncommitted changes on `feat/epic-28-gateway-foundation`.

        | Code | Skill | Description |
        |------|-------|-------------|
        | **[BP]** | `bmad-brainstorming` | Brainstorm what Phase 13 should focus on |
        | **[PRD]** | `bmad-prd` | Create/update a PRD for the next set of features |

        ---

        ### 💡 My Recommendation

        1. **`bmad-brainstorming`** to explore what's next for Axion
        2. **`bmad-generate-project-context`** to refresh the LLM context

        Would you like me to run any of these for you right now?

        [结果] BMad Help: 所有 32 个 Epic 已完成，推荐下一步规划新阶段或刷新项目上下文
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result.contains("## 🎯 BMad Help — Axion Project Status"))
        #expect(result.contains("### Where You Are"))
        #expect(result.contains("| Phase | Description | Status |"))
        #expect(result.contains("| **[PRD]** | `bmad-prd` |"))
        #expect(result.contains("### 💡 My Recommendation"))
        #expect(result.contains("Would you like me to run any of these for you right now?"))
        #expect(!result.contains("[结果]"))
        #expect(!result.hasPrefix("BMad Help: 所有 32 个 Epic 已完成"))
    }

    @Test("cleanResultText keeps top BMad project overview from real gateway output")
    func cleanResultTextKeepsTopBMadProjectOverview() {
        let text = """
        Now I have the full picture. Here's the BMad Help summary:

        ---

        ## 🧭 BMad 帮助 — 项目状态总览

        ### 📍 你当前的位置

        **项目**: Axion
        **模块**: BMad Method v6.8.0 + TEA v1.19.0 + Automator
        **当前分支**: `feat/epic-28-gateway-foundation`（有 12 个未暂存修改文件）

        ### ✅ 已完成的阶段

        | 阶段 | 状态 |
        |------|------|
        | **1-Analysis** (研究/头脑风暴) | ✅ 已有 project-context.md |
        | **2-Planning** (PRD/UX) | ✅ PRD + Architecture 已完成 |
        | **3-Solutioning** (架构/Epics) | ✅ Epics + 实现就绪报告已就绪 |
        | **4-Implementation** (Sprint执行) | ✅ **所有 32 个 Epic 全部 Done** |

        所有 32 个 Epic 已完成，包含回顾都已归档。这是一个里程碑！🎉

        ### ⚠️ 当前未提交的工作

        分支 `feat/epic-28-gateway-foundation` 上有 **12 个未暂存的修改文件**，看起来是 Epic 32 完成后的一些额外增强工作（TG streaming、event handling、message UX 改进）。这些改动还没有 commit。

        ---

        ### 🎯 建议的下一步行动

        **1. 处理未提交的改动**（最优先）
        - 这些改动需要提交或 stashed。你可以让我帮你：
          - 查看改动内容并提交
          - 或者运行 `bmad-code-review` (CR) 先做代码审查

        **2. Sprint 完成后的可选操作**

        | 代码 | 技能 | 说明 |
        |------|-------|------|
        | **ER** | `bmad-retrospective` | 做一次整体回顾（所有 Epic 已完成） |
        | **QQ** | `bmad-quick-dev` | 快速实现小型改进或修复 |
        | **CC** | `bmad-correct-course` | 如果需要规划下一个大方向 |
        | **CR** | `bmad-code-review` | 对当前未提交改动做代码审查 |

        **3. 如果你准备开启新阶段**

        当前所有 32 个 Epic 都已完成，你可能需要：
        - 更新 PRD 或 Architecture 来规划下一批 Epic
        - 运行 `bmad-prd` (PRD) 来更新产品需求
        - 运行 `bmad-create-architecture` (CA) 来更新技术架构
        - 然后运行 `bmad-create-epics-and-stories` (CE) 创建新 Epic

        ---

        需要我帮你做什么？例如：
        - 🔍 **审查当前未提交的代码** → 我可以运行 `bmad-code-review`
        - 📦 **提交当前改动** → 我可以直接帮你 commit
        - 🗺️ **规划下一阶段** → 运行 `bmad-correct-course` 或更新 PRD

        [结果] BMad Help: 所有32个Epic已完成，有12个未提交文件，建议先处理改动再规划下一阶段
        """

        let result = TGEventHandler.cleanResultText(from: text)

        #expect(result.contains("## 🧭 BMad 帮助 — 项目状态总览"))
        #expect(result.contains("### 📍 你当前的位置"))
        #expect(result.contains("**项目**: Axion"))
        #expect(result.contains("### ✅ 已完成的阶段"))
        #expect(result.contains("所有 32 个 Epic 已完成"))
        #expect(result.contains("### ⚠️ 当前未提交的工作"))
        #expect(result.contains("### 🎯 建议的下一步行动"))
        #expect(result.contains("需要我帮你做什么？例如："))
        #expect(!result.contains("[结果]"))
    }

    @Test("cleanResultText extracts multiline latest result block")
    func cleanResultTextExtractsMultilineLatestResult() {
        let text = """
        [结果] 旧答案

        这是上一轮的内容。

        [结果]
        第一行答案
        第二行答案
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result == "第一行答案\n第二行答案")
    }

    @Test("cleanResultText keeps short terminal answer after MCP output")
    func cleanResultTextKeepsShortTerminalAnswer() {
        let text = """
        🌐 Z.ai Built-in Tool: webReader

        Input:
        {"url":"https://example.com"}

        Output:
        {"ok":true}

        42
        """

        let result = TGEventHandler.cleanResultText(from: text)
        #expect(result == "42")
    }
}
