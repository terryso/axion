# Story Automator Learnings

## Run: 2026-05-22

**Epic:** 记忆进化 — ExperienceExtractor 与自动审查
**Stories:** 21.2, 21.3, 21.4

### Patterns Observed
- All 3 stories completed cleanly on first attempt — Low complexity stories run smoothly
- No code review cycles needed (all passed review on cycle 1)
- Agent: all-claude preset worked well for Low complexity stories

### Code Review Insights
- Common issues: None (all passed first cycle)
- Average cycles to clean: 1

### Timing Estimates
- create-story: ~5-8 min per story
- dev-story: ~10-15 min per story
- automate: ~5 min per story
- code-review: ~10-15 min per cycle

### Recommendations for Future Runs
- All-claude preset is efficient for Low complexity stories
- Consider maxParallel=2 for stories with no shared file dependencies

## Run: 2026-05-23T10:52:04Z

**Epic:** 后台审查代理 — 闭环学习核心引擎 (Epic 24)
**Stories:** 24.1, 24.2, 24.3, 24.4

### Patterns Observed
- All 4 stories completed cleanly on first attempt with claude agent
- Code reviews passed on cycle 1 for both 24.3 and 24.4
- Low complexity stories — all scored "low" by the complexity engine
- No fallback agent needed (no fallback configured)

### Code Review Insights
- Common issues: None (all reviews passed cycle 1)
- Average cycles to clean: 1

### Timing Estimates
- create-story: ~5-10 min
- dev-story: ~10-25 min
- automate: ~5-10 min
- code-review: ~10-15 min per cycle

### Recommendations for Future Runs
- Sprint-compare script has a key format mismatch (story "24.1" vs entry "24-1-...") causing false positives — should be fixed
- All low-complexity stories can safely use claude without fallback
