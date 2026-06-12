# /apps List Size Column

Baseline: `a503cda0dd7e`

## Intent

The `/apps` candidate list must make app disk usage visible enough to support uninstall decisions. The list already carried `sizeBytes`, but the column was unlabeled and the default reader often returned `0` for `.app` bundles, rendering as `-`.

## Implementation

- Added an explicit list header with `名称`, `Bundle ID`, `版本`, `大小`, `状态`, and `来源` in `AppListFormatter.renderList`.
- Updated `AppListService.defaultSizeReader` to resolve a root symlinked app bundle, enumerate bundle contents, and sum file allocated sizes with logical-size fallback.
- Kept detail view behavior unchanged; it continues to show the same formatted size through `formatBytes`.

## Files

- `Sources/AxionCLI/Services/Storage/App/AppListFormatter.swift`
- `Sources/AxionCLI/Services/Storage/App/AppListService.swift`
- `Tests/AxionCLITests/Services/AppListServiceTests.swift`

## Verification

Passed:

- `swift test --filter AppListServiceTests`
- `swift test --filter SlashCommandAppsTests`
- `swift test --filter AppSelectionPromptTests`
- `git diff --check`
- `grep -rl "import XCTest" Tests/ || true`

Attempted:

- `swift test --parallel --num-workers 1 --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"`

Result: failed outside this change in `CuratorSchedulerTests.swift` with nil callback expectations and an unexpected signal 5 from `swiftpm-testing-helper`.
