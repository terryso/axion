---
title: 'Arch detail upgrade plan display'
type: 'feature'
created: '2026-06-16'
status: 'done'
baseline_commit: '4da0e594a6dba170288d2bd87e4af90fa8091199'
context:
  - '{project-root}/_bmad-output/specs/spec-arch-upgrade-workflow/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-arch-upgrade-workflow/upgrade-workflow.md'
  - '{project-root}/_bmad-output/project-context.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `/arch` now lets users open a detail page, but the detail must explain the architecture remediation path, not merely run a same-prefix version upgrade. Users need to see and confirm whether an Intel-only item can be replaced by an Apple Silicon or Universal binary.

**Approach:** Add an AppArchitecture upgrade planning model/protocol and a local planner that classifies Homebrew formula paths into either same-prefix `brew upgrade <formula>` plans or `/usr/local` Intel Homebrew migration plans. `/usr/local/Cellar` migration installs the formula with Apple Silicon Homebrew first, then uninstalls the Intel Homebrew formula only after install success. MacPorts, direct `.app`, system apps, and unknown items remain manual or unsupported. Inject the plan only into interactive `/arch` detail rendering; keep `AppArchitectureScanService` side-effect free and keep `axion arch` table output unchanged.

## Boundaries & Constraints

**Always:** Keep `AppArchitectureScanService` read-only. Use Swift Testing only. Planner tests must use constructed fixtures and injected/local values, not real `brew`, `port`, `mas`, network, Helper, or OS package-manager state. `/arch` list navigation, detail navigation, Esc/Ctrl-C behavior, non-TTY fallback, and `axion arch` non-interactive output must remain compatible with the current behavior.

**Ask First:** Ask before adding cask token resolution, MacPorts execution, App Store automation, direct downloads, history persistence, support-data deletion, or any package manager beyond the currently approved Homebrew formula execution path. Ask before changing the columns or content of `axion arch` table output.

**Never:** Do not execute `port`, `mas`, `open`, `osascript`, sudo, direct file deletion, system update commands, or support-data deletion from `/arch`. Do not add side effects to the scanner. Do not implement Homebrew cask execution, MacPorts execution, App Store automation, or direct downloads in this change. Homebrew package uninstall is allowed only as the second step of the approved `/usr/local` Intel-to-native migration plan after native install succeeds.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Apple Silicon Homebrew formula detail | `/arch` detail item has source `.homebrew` and real path under `/opt/homebrew/Cellar/foo/...` | Detail includes upgrade status, package identity `foo`, command display `brew upgrade foo`, `sudo: no`, confidence, and post-check path | If path cannot produce a formula name, show unsupported/manual guidance and no executable action |
| Intel Homebrew formula detail | `/arch` detail item has source `.homebrew` and real path under `/usr/local/Cellar/foo/...` | Detail includes migration commands `/opt/homebrew/bin/brew install foo` then `/usr/local/bin/brew uninstall foo`, plus notes that `brew upgrade` cannot change prefix architecture | If native install fails, do not run the Intel uninstall command |
| MacPorts detail | item source `.macPorts` | Detail shows manual guidance such as checking MacPorts upgrade path; no executable action or command execution | No real `port` call; unsupported status is display-only |
| Direct app detail | non-system `.application` item under `/Applications` or another app path | Detail shows manual vendor-update guidance and no automatic upgrade plan | No download, no Sparkle parsing, no external process |
| System app detail | `.application` item with `isSystemApp == true` | Detail says system apps should be handled through macOS updates; no executable action | No system update command |
| Unknown architecture/detail | item category `.unknown` or unmatched path/source | Detail shows unknown/unsupported guidance without crashing | Empty executable path and unusual paths render safely |

</frozen-after-approval>

## Code Map

- `Sources/AxionCLI/Services/AppArchitecture/AppArchitectureScanService.swift` -- existing scan models and scanner; should remain read-only and only supply item facts.
- `Sources/AxionCLI/Services/AppArchitecture/AppArchitectureFormatter.swift` -- current table/list/detail renderer; Phase 1 should add optional upgrade-plan detail rendering without changing non-interactive table output.
- `Sources/AxionCLI/Chat/AppArchitectureSelectionPrompt.swift` -- current `/arch` list/detail state machine; should await a planner only when entering detail, mirroring the async-detail pattern used by `/apps`.
- `Sources/AxionCLI/Commands/ChatCommand.swift` -- `/arch` entry point; should inject the default planner into the prompt and continue to use the scan service only for scanning.
- `Sources/AxionCLI/Commands/ArchitectureCommand.swift` -- `axion arch` non-interactive command; should not receive the upgrade planner or changed output.
- `Tests/AxionCLITests/Services/AppArchitectureScanServiceTests.swift` -- existing scanner/formatter coverage; add or mirror focused planner tests without real external dependencies.
- `Tests/AxionCLITests/Chat/AppArchitectureSelectionPromptTests.swift` -- existing `/arch` prompt behavior coverage; add detail rendering coverage with a mock planner.

## Tasks & Acceptance

**Execution:**
- [x] `Sources/AxionCLI/Services/AppArchitecture/AppArchitectureUpgradePlanning.swift` -- add upgrade status/confidence/plan models, `AppArchitectureUpgradePlanning` protocol, and default planner -- isolates upgrade decisions from scanning and keeps planning deterministic and side-effect free.
- [x] `Sources/AxionCLI/Services/AppArchitecture/AppArchitectureFormatter.swift` -- extend `renderDetail` to accept an optional plan and render upgrade status, package identity, command display, sudo requirement, confidence, post-check path, and notes -- makes the detail page useful without changing list/table output.
- [x] `Sources/AxionCLI/Chat/AppArchitectureSelectionPrompt.swift` -- make the prompt await an optional planner when opening detail and pass the resulting plan to the formatter -- keeps planning scoped to interactive detail.
- [x] `Sources/AxionCLI/Commands/ChatCommand.swift` -- wire the default planner into `/arch` prompt -- enables the feature in chat mode while leaving `axion arch` untouched.
- [x] `Tests/AxionCLITests/Services/AppArchitectureUpgradePlanningTests.swift` -- add fixture-based Swift Testing coverage for Homebrew formula, MacPorts, direct app, system app, and unknown cases -- verifies deterministic planning without real package managers.
- [x] `Tests/AxionCLITests/Chat/AppArchitectureSelectionPromptTests.swift` -- update existing async prompt expectations and add detail-plan rendering coverage -- prevents regressions in list/detail behavior.
- [x] Existing command/formatter tests -- keep or add assertions that `AppArchitectureFormatter.render(_:)` and `ArchitectureCommand` output do not include upgrade plan details -- protects script-friendly output.
- [x] `Sources/AxionCLI/Services/AppArchitecture/AppArchitectureDetailAnalysisService.swift` -- add cached/injected detail analysis for `/arch` detail -- helps users understand what an app/tool/library is before deciding upgrade vs uninstall.
- [x] `/arch` direct app uninstall review handoff -- detail Enter returns a generated `scan_app_uninstall` task for non-system `.app` items -- removes the extra manual `/apps <app>` step while preserving existing approval safeguards.
- [x] `Sources/AxionCLI/Services/AppArchitecture/AppArchitectureUpgradeExecution.swift` -- add mockable Homebrew upgrade execution and post-upgrade rescan protocols -- enables Phase 2 `u` for high-confidence Homebrew formula plans without using shell string concatenation.
- [x] Homebrew upgrade progress display -- stream brew stdout/stderr into the `/arch` running page with elapsed time and recent output lines -- gives users visible progress without inventing unreliable percentages.
- [x] Architecture outcome gating and Intel Homebrew migration -- distinguish command success from architecture remediation success, and turn `/usr/local/Cellar` Intel Homebrew prefix items into install-native-then-uninstall-Intel migration plans -- keeps `/arch` focused on replacing Intel-only binaries, not merely updating version numbers.
- [x] Post-upgrade list refresh -- after a successful upgrade result, `b` / left-arrow back to the list reruns the original `/arch` scan options and redraws the candidate list -- prevents stale Intel-only rows from remaining visible after remediation.

**Acceptance Criteria:**
- Given a Homebrew formula item with display or executable path under `/opt/homebrew/Cellar`, when the user opens `/arch` detail, then the detail shows `brew upgrade <formula>` and offers `u` execution after confirmation.
- Given a Homebrew formula item with display or executable path under `/usr/local/Cellar`, when the user opens `/arch` detail, then the detail shows `/opt/homebrew/bin/brew install <formula>` followed by `/usr/local/bin/brew uninstall <formula>` and offers `u` execution after confirmation.
- Given MacPorts, direct app, system app, or unknown items, when the user opens `/arch` detail, then the detail shows manual or unsupported guidance and no executable upgrade action.
- Given `axion arch` is run non-interactively, when output is rendered, then the existing table/list output remains upgrade-plan free.
- Given `/arch` is used in non-TTY mode, when the command renders candidates, then it still only renders the numbered list and does not plan upgrades.
- Given current `/arch` list/detail keyboard flows, when tests navigate with Enter, `b`, arrows, `q`, Esc, or Ctrl-C, then behavior does not regress.
- Given a non-system direct `.app` item is open in `/arch` detail, when the user presses Enter, then Axion enters the existing App uninstall review flow by generating a `scan_app_uninstall` task and still does not execute deletion directly.
- Given a package, system app, or unsupported item is open in `/arch` detail, when the user presses Enter, then `/arch` does not trigger package/system uninstall execution.
- Given a high-confidence Homebrew formula item is open in `/arch` detail, when the user presses `u` then confirms with `y`, then Axion executes the structured `brew upgrade <formula>` plan through the injected executor and renders the command result plus a post-upgrade rescan summary.
- Given the same Homebrew upgrade confirmation is cancelled, or the plan requires sudo / has no executable command / is manual-only, then no process launcher is called.
- Given Homebrew emits stdout or stderr while upgrading, when the process is still running, then the detail page refreshes with elapsed time and the latest sanitized output lines.
- Given a Homebrew command exits successfully but the post-upgrade rescan still reports Intel-only, then the result page reports that the architecture goal was not achieved and recommends native `/opt/homebrew` migration when the path remains under `/usr/local/Cellar`.
- Given a Homebrew formula path is under `/usr/local/Cellar`, then `u` runs native install first and only runs Intel formula uninstall if the native install exits successfully.
- Given a Homebrew upgrade succeeds and the user presses `b` from the result page, then `/arch` reruns the list scan with the original scan options before rendering the list.
- Given a Homebrew upgrade fails and the user presses `b` from the result page, then `/arch` returns to the existing list without an extra list rescan.

## Spec Change Log

- 2026-06-16 follow-up: User noted that returning from a successful upgrade result should refresh the list. The prompt now marks successful upgrade results for a one-shot list rescan on `b` / left-arrow, using the original scan options.
- 2026-06-16 follow-up: User clarified that the goal is architecture replacement, not same-prefix version upgrade. `/usr/local/Cellar` now generates an executable Homebrew migration plan: install through `/opt/homebrew/bin/brew`, then uninstall through `/usr/local/bin/brew` only after install success.
- 2026-06-16 follow-up: User pointed out that a successful `brew upgrade` can still leave the binary Intel-only. Result rendering now separates command status from architecture outcome and recommends native `/opt/homebrew` remediation when rescans stay under `/usr/local/Cellar`.
- 2026-06-16 follow-up: User asked whether upgrade progress can be shown. Added streaming stdout/stderr progress from the Homebrew process into the running page; no percentage is shown because Homebrew does not provide a stable progress metric.
- 2026-06-16 follow-up: User asked why Homebrew upgrades cannot provide an operation instead of asking the user to run the command manually. Scope advanced to the minimal Phase 2 Homebrew formula execution path: `u` on executable Homebrew plans, `y` confirmation, structured process launching, and post-upgrade rescan display.
- 2026-06-16 follow-up: User clarified that `/arch` detail should not force users to return and type `/apps <app>` for uninstall review. Scope was renegotiated to let non-system direct `.app` detail press Enter to generate the existing `scan_app_uninstall` review task, without executing deletion. Package uninstall remains manual/unsupported.
- 2026-06-16 follow-up: User requested app/library purpose analysis in `/arch` detail. Added an injected/cached detail analysis provider for interactive detail only; non-interactive `axion arch` output remains unchanged.

## Design Notes

The default planner should be deterministic and side-effect free. Homebrew formula detection can use the same real-path assumption as scanning: match `.../Cellar/<formula>/...` and set `packageIdentity` to `<formula>`. `/opt/homebrew/Cellar` renders and executes same-prefix `brew upgrade <formula>`. `/usr/local/Cellar` renders and executes an architecture migration plan: `/opt/homebrew/bin/brew install <formula>` followed by `/usr/local/bin/brew uninstall <formula>` only after the native install succeeds. The post-upgrade rescan is the source of truth for whether the architecture goal was achieved.

`AppArchitectureSelectionPrompt` can follow the `/apps` prompt pattern by becoming async and rendering detail after awaiting injected data. Tests should inject a mock planner; production should use the default planner. `AppArchitectureFormatter.render(_:)` for the non-interactive command should not receive a plan parameter.

## Verification

**Commands:**
- `swift test --filter AppArchitectureUpgradePlanningTests` -- expected: new planner cases pass without invoking external package managers.
- `swift test --filter AppArchitectureSelectionPromptTests` -- expected: `/arch` list/detail navigation and plan rendering tests pass.
- `swift test --filter AppArchitectureScanServiceTests --filter ArchitectureCommandTests --filter SlashCommandArchitectureTests` -- expected: scanner, formatter, command parsing, and slash metadata remain compatible.
- `swift test --filter "AxionHelperTests.Tools" --filter "AxionHelperTests.Models" --filter "AxionHelperTests.MCP" --filter "AxionHelperTests.Services" --filter "AxionCoreTests" --filter "AxionCLITests"` -- expected: project unit-test set passes.

## Suggested Review Order

**Interactive Detail Wiring**

- Start here to see where `/arch` detail planning is invoked.
  [`AppArchitectureSelectionPrompt.swift:92`](../../Sources/AxionCLI/Chat/AppArchitectureSelectionPrompt.swift#L92)

- Production `/arch` injects the default planner only for chat detail flow.
  [`ChatCommand.swift:1012`](../../Sources/AxionCLI/Commands/ChatCommand.swift#L1012)

**Planning Model**

- The new plan/protocol isolates upgrade and migration decisions from scanning.
  [`AppArchitectureUpgradePlanning.swift:15`](../../Sources/AxionCLI/Services/AppArchitecture/AppArchitectureUpgradePlanning.swift#L15)

- Homebrew plans come only from safe Cellar formula paths.
  [`AppArchitectureUpgradePlanning.swift:114`](../../Sources/AxionCLI/Services/AppArchitecture/AppArchitectureUpgradePlanning.swift#L114)

- Manual and unsupported paths avoid command execution for non-Homebrew sources.
  [`AppArchitectureUpgradePlanning.swift:60`](../../Sources/AxionCLI/Services/AppArchitecture/AppArchitectureUpgradePlanning.swift#L60)

**Rendering Boundary**

- Detail rendering accepts a plan without changing table/list output.
  [`AppArchitectureFormatter.swift:139`](../../Sources/AxionCLI/Services/AppArchitecture/AppArchitectureFormatter.swift#L139)

- Upgrade-plan lines centralize labels, command display, and safety notes.
  [`AppArchitectureFormatter.swift:339`](../../Sources/AxionCLI/Services/AppArchitecture/AppArchitectureFormatter.swift#L339)

**Regression Tests**

- Planner fixtures cover Homebrew, unsafe paths, MacPorts, apps, system, unknown.
  [`AppArchitectureUpgradePlanningTests.swift:7`](../../Tests/AxionCLITests/Services/AppArchitectureUpgradePlanningTests.swift#L7)

- Prompt tests cover detail rendering, non-TTY skip, q, Ctrl-C, and navigation.
  [`AppArchitectureSelectionPromptTests.swift:117`](../../Tests/AxionCLITests/Chat/AppArchitectureSelectionPromptTests.swift#L117)

- Command output stays upgrade-plan free through injected scanner coverage.
  [`ArchitectureCommandTests.swift:53`](../../Tests/AxionCLITests/Commands/ArchitectureCommandTests.swift#L53)
