---
name: epic24-retrospective
description: Epic 24 review agent pipeline complete, 5571 tests, fire-and-forget pattern, prefix cache sharing
metadata:
  type: project
---

Epic 24 (后台审查代理) complete — full Hermes-style review pipeline: fork → inject tools → execute → summarize. 5,571 tests, +330 this epic. Fire-and-forget pattern for sessionEnd hook. Prefix cache sharing via `cachedSystemPrompt` + `_rawSystemPromptMode`. No Epic 25 defined.

**Why:** Self-evolution track is complete with this epic. Future work would be enhancements (review callbacks, history dedup, AgentOptions decomposition).
**How to apply:** The review pipeline is the canonical way to add background agent processing. Future agent types (e.g., "planning agent", "critique agent") should follow the same factory + tools + orchestrator pattern.
