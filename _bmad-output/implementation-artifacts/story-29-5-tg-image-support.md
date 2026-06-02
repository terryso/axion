---
story_id: 29.5
epic: 29
title: TG 图片支持
status: in-progress
created: 2026-05-29
---

# Story 29.5: TG 图片支持

As a Axion 用户,
I want 通过 TG 发送图片给 Axion,
So that 我可以提供截图或照片作为任务上下文.

## Acceptance Criteria

**AC1:** 白名单用户发送图片 → 从 PhotoSize 数组选取最大尺寸 → 通过 getFile API 获取文件路径 → 下载到临时文件 → 图片作为附件传入 agent 上下文

**AC2:** 图片下载失败 → TG 回复 "图片下载失败，请重试" → 临时文件已清理

## Implementation Notes

- Add `photo` field to `TGMessage`, add `TGPhotoSize` and `TGFile` models
- Add `getFile` and `downloadFile` to `TGAPIClientProtocol` and `TGAPIClient`
- Update `TelegramAdapter.processMessage` to handle photo messages
- MVP: image saved to temp file, path included in task prompt text
- Unit tests only (mock-based, no real TG API calls)
