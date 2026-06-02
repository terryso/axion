---
title: 'TG /skills 内联键盘分页'
type: 'feature'
created: '2026-06-02'
status: 'in-progress'
context: []
---

<frozen-after-approval reason="人工意图 — 除非用户重新协商，否则不可修改">

## 意图

**问题：** TG `/skills` 命令目前以纯文本返回所有技能的名字和描述，内容冗长，技能数量多时体验差。

**方案：** 改用 Telegram 内联键盘视图展示技能列表。每个技能只显示名字作为按钮（不显示描述），每页 20 条，底部有 Prev/Next 翻页按钮。风格对标 Claude Code 的简洁技能列表。

## 边界与约束

**始终遵守：** 使用已有的 `TGInlineKeyboardMarkup` 和 `TGCallbackData` 模式。按钮文字只用技能名字。每页 20 条。

**需先确认：** 无。

**不做：** 不加技能描述。不加外部依赖。不改 CLI `SkillListCommand` 和 HTTP API 的技能列表逻辑。

## I/O 与边界场景矩阵

| 场景 | 输入 / 状态 | 预期输出 / 行为 | 错误处理 |
|------|------------|----------------|---------|
| 正常 /skills | 用户发送 `/skills`，有 25 个技能 | 内联键盘显示前 20 个技能名按钮 + Next 按钮 | N/A |
| 翻到第 2 页 | 用户在第 1 页点 Next | 消息被编辑为第 21-25 个技能 + Prev 按钮 | N/A |
| 单页场景 | 注册技能 < 20 个 | 内联键盘显示所有技能，无翻页按钮 | N/A |
| 零技能 | 无注册技能 | 纯文本 "暂无可用技能"（保持现有行为） | N/A |
| 最后一页 | 用户在末页 | 显示剩余技能 + Prev 按钮（无 Next） | N/A |
| 过期翻页 | 用户点击旧消息上的按钮 | answerCallbackQuery 返回 "已过期" | N/A |

</frozen-after-approval>

## 代码地图

- `Sources/AxionCLI/Services/Telegram/TGCommandRegistry.swift` — TGCommandDef 需支持返回 markup
- `Sources/AxionCLI/Services/Telegram/TGCommandRouter.swift` — Router 需传播 markup 结果
- `Sources/AxionCLI/Services/Telegram/TGInteractiveSessionStore.swift` — TGCallbackAction 增加 `.skillsPage`
- `Sources/AxionCLI/Services/Telegram/TelegramAdapter.swift` — 处理 markup 返回，处理 skillsPage 回调
- `Sources/AxionCLI/Commands/GatewayCommand.swift` — formatSkills 改为生成内联键盘
- `Sources/AxionCLI/Services/Telegram/TGModels.swift` — 无需修改（TGInlineKeyboardButton 已支持 callbackData）

## 任务与验收

**执行步骤：**
- [x] `TGCommandRegistry.swift` — 将 `handler` 返回类型从 `String` 改为 `(text: String, markup: TGInlineKeyboardMarkup?)`。现有命令统一返回 `(text, nil)`。
- [x] `TGCommandRouter.swift` — `handle()` 返回类型改为 `(text: String, markup: TGInlineKeyboardMarkup?)?`。
- [x] `TGInteractiveSessionStore.swift` — `TGCallbackAction` 新增 `.skillsPage` case。
- [x] `TelegramAdapter.swift` — (a) `processMessage` 中 markup 非空时调用 `sendWithMarkup`。(b) init 增加 `skillsProvider` 参数。(c) `processCallback` 中处理 `.skillsPage` 回调，编辑消息显示目标页。
- [x] `GatewayCommand.swift` — `formatSkills` 改为返回 `(text: String, markup: TGInlineKeyboardMarkup?)`，生成每行 2 个技能按钮、每页 20 条 + Prev/Next 导航行。将 `skillsProvider` 注入 TelegramAdapter。
- [x] 更新测试：`TGCommandRegistryTests`、`TGCommandRouterTests`、`TelegramAdapterTests` 适配新签名和回调行为。

**验收标准：**
- Given 用户发送 `/skills` 且注册了 25 个技能，when 命令处理完成，then 显示内联键盘含 20 个技能名按钮 + Next 按钮；点 Next 后消息编辑为剩余 5 个技能 + Prev 按钮。
- Given 用户发送 `/skills` 且注册了 15 个技能，then 显示内联键盘含 15 个技能名按钮，无翻页按钮。
- Given 用户发送 `/skills` 且无注册技能，then 返回纯文本 "暂无可用技能"。

## Spec 变更日志

## 设计说明

回调数据格式：`skillsPage:<pageNumber>:0`，`detail` 字段存储页码（0 起始），`pendingId` 不使用（填 `0`）。`processCallback` 中解析 `detail` 为 Int，从 `skillsProvider` 获取技能列表，构建目标页的键盘，编辑原消息。

按钮布局：每行 2 个技能按钮。底部导航行放 Prev/Next（单行 1-2 个按钮）。

## 验证

**命令：**
- `swift build` — 预期：编译通过
- `swift test --filter "AxionCLITests.Services.Telegram"` — 预期：全部测试通过
