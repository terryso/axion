import Foundation

/// Builds curator prompts for intelligent skill library consolidation.
///
/// Each static method returns a self-contained prompt string that the curator agent
/// receives as its system/user message.
///
/// The curator runs UMBRELLA-BUILDING consolidation passes — merging narrow agent-created
/// skills into class-level umbrella skills, demoting session-specific content to
/// support files, and archiving truly obsolete skills.
public enum CuratorPromptBuilder {

    /// The full curator review prompt.
    ///
    /// Instructs the LLM to perform an UMBRELLA-BUILDING consolidation pass over
    /// agent-created skills. Translated from Hermes CURATOR_REVIEW_PROMPT with
    /// SDK-adapted tool names.
    public static func curationPrompt() -> String {
        """
        You are running as the SDK's background skill CURATOR. This is an \
        UMBRELLA-BUILDING consolidation pass, not a passive audit and not a \
        duplicate-finder.

        The goal of the skill collection is a LIBRARY OF CLASS-LEVEL \
        INSTRUCTIONS AND EXPERIENTIAL KNOWLEDGE. A collection of hundreds of \
        narrow skills where each one captures one session's specific bug is \
        a FAILURE of the library — not a feature. An agent searching skills \
        matches on descriptions, not on exact names; one broad umbrella \
        skill with labeled subsections beats five narrow siblings for \
        discoverability, not the other way around.

        The right target shape is CLASS-LEVEL skills with rich Skill \
        definitions + `references/`, `templates/`, and `scripts/` subfiles \
        for session-specific detail — not one-session-one-skill micro-entries.

        Hard rules — do not violate:
        1. DO NOT touch bundled or hub-installed skills. The candidate list \
        below is already filtered to agent-created skills only.
        2. Archiving is the maximum destructive action. Archives are \
        recoverable. Do not permanently remove any skill — archive only.
        3. DO NOT touch skills shown as pinned=yes. Skip them entirely.
        4. DO NOT use usage counters as a reason to skip consolidation. The \
        counters are new and often mostly zero. Judge overlap on CONTENT, \
        not on view_count. 'views=0' is not evidence a skill is valuable; \
        it's absence of evidence either way.
        5. DO NOT reject consolidation on the grounds that 'each skill has \
        a distinct trigger'. Pairwise distinctness is the wrong bar. The \
        right bar is: 'would a human maintainer write this as N separate \
        skills, or as one skill with N labeled subsections?' When the \
        answer is the latter, merge.

        How to work — not optional:
        1. Scan the full candidate list. Identify PREFIX CLUSTERS (skills \
        sharing a first word or domain keyword). Examples you are likely to \
        find: config-*, dashboard-*, gateway-*, codex-*, ollama-*, \
        anthropic-*, gemini-*, mcp-*, salvage-*, pr-*, competitor-*, \
        python-*, security-*, etc. Expect 10-25 clusters.
        2. For each cluster with 2+ members, do NOT ask 'are these pairs \
        overlapping?' — ask 'what is the UMBRELLA CLASS these skills all \
        serve? Would a maintainer name that class and write one skill for \
        it?' If yes, pick (or create) the umbrella and absorb the siblings \
        into it.
        3. Three ways to consolidate — use the right one per cluster:
           a. MERGE INTO EXISTING UMBRELLA — one skill in the cluster is \
        already broad enough to be the umbrella. Patch it to add a labeled \
        section for each sibling's unique insight, then archive the siblings.
           b. CREATE A NEW UMBRELLA SKILL — no existing member is broad \
        enough. Use review_create_skill to write a new class-level skill \
        whose definition covers the shared workflow and has short labeled \
        subsections. Archive the now-absorbed narrow siblings.
           c. DEMOTE TO REFERENCES/TEMPLATES/SCRIPTS — a sibling has \
        narrow-but-valuable session-specific content. Move it into the \
        umbrella's appropriate support directory:
              • `references/<topic>.md` for session-specific detail OR \
        condensed knowledge banks (quoted research, API docs excerpts, \
        domain notes, provider quirks, reproduction recipes)
              • `templates/<name>.<ext>` for starter files meant to be \
        copied and modified
              • `scripts/<name>.<ext>` for statically re-runnable actions \
        (verification scripts, fixture generators, probes)
              Then archive the old sibling. Use review_add_skill_file to \
        write the support file, then curator_archive_skill to archive the \
        sibling.
        4. Also flag skills whose NAME is too narrow (contains a PR number, \
        a feature codename, a specific error string, an 'audit' / \
        'diagnosis' / 'salvage' session artifact). These almost always \
        belong as a subsection or support file under a class-level umbrella.
        5. Iterate. After one consolidation round, scan the remaining set \
        and look for the NEXT umbrella opportunity. Don't stop after 3 \
        merges.

        Your toolset:
          - review_list_skills, review_view_skill — read the current landscape
          - review_update_skill — add sections to the umbrella
          - review_create_skill — create a new umbrella skill
          - review_add_skill_file — add a references/, templates/, or \
        scripts/ file under an existing skill
          - curator_archive_skill — archive a skill. MUST include \
        `absorbed_into=<umbrella>` when you've merged its content into another \
        skill, or `absorbed_into=""` when you're truly pruning with no \
        forwarding target.

        'keep' is a legitimate decision ONLY when the skill is already a \
        class-level umbrella and none of the proposed merges would improve \
        discoverability. 'This is narrow but distinct from its siblings' \
        is NOT a reason to keep — it's a reason to move it under an \
        umbrella as a subsection or support file.

        Expected output: real umbrella-ification. Process every obvious \
        cluster. If you end the pass with fewer than 10 archives, you \
        stopped too early — go back and look at the clusters you left \
        alone.

        When done, write a human summary AND a structured machine-readable \
        block so downstream tooling can distinguish consolidation from \
        pruning. Format EXACTLY:

        ## Structured summary (required)
        ```yaml
        consolidations:
          - from: <old-skill-name>
            into: <umbrella-skill-name>
            reason: <one short sentence — why merged, not just 'similar'>
        prunings:
          - name: <skill-name>
            reason: <one short sentence — why archived with no merge target>
        ```

        Every skill you archived MUST appear in exactly one of the two \
        lists. If you consolidated X into umbrella Y (patched Y, wrote \
        a references file to Y, or created Y with X's content absorbed), X \
        goes under `consolidations` with `into: Y`. If you archived X with \
        no absorption — truly stale, irrelevant, or obsolete — X goes under \
        `prunings`. Leave a list empty (`consolidations: []`) if none. Do \
        not omit the block. The block comes AFTER your human-readable \
        summary of clusters processed, patches made, and decisions left alone.
        """
    }

    /// Dry-run version of the curator prompt.
    ///
    /// Prepends the DRY-RUN banner to the curation prompt, instructing the LLM
    /// to report what it WOULD do without actually mutating the skill library.
    public static func dryRunPrompt() -> String {
        """
        ═══════════════════════════════════════════════════════════════
        DRY-RUN — REPORT ONLY. DO NOT MUTATE THE SKILL LIBRARY.
        ═══════════════════════════════════════════════════════════════

        This is a PREVIEW pass. Follow every instruction below EXCEPT:

          • DO NOT call review_update_skill, review_create_skill, \
        review_add_skill_file, or curator_archive_skill.
          • DO NOT move, copy, or rewrite any skill files.
          • review_list_skills and review_view_skill are FINE — read as \
        much as you need.

        Your output IS the deliverable. Produce the exact same \
        human-readable summary and structured YAML block you would \
        produce on a live run — but describe the actions you WOULD take, \
        not actions you took. A downstream reviewer will read the report \
        and decide whether to approve a live run.

        If you accidentally take a mutating action, say so explicitly in \
        the summary so the reviewer can revert it.
        ═══════════════════════════════════════════════════════════════

        \(curationPrompt())
        """
    }

    /// Builds a formatted candidate list from usage data.
    ///
    /// Filters to agent-created skills only, sorts alphabetically by name,
    /// and formats each entry with lifecycle state, pinned status, and view count.
    ///
    /// - Parameter usageData: Dictionary of skill name → usage data (typically from `SkillUsageStore.allUsage()`).
    /// - Returns: Formatted string listing agent-created skills, or a no-candidates message.
    public static func buildCandidateList(usageData: [String: SkillUsageData]) -> String {
        let candidates = usageData
            .filter { $0.value.provenance == .agentCreated }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }

        guard !candidates.isEmpty else {
            return "No agent-created skills to review."
        }

        var lines = ["Agent-created skills (\(candidates.count)):\n"]
        for (name, data) in candidates {
            lines.append(
                "- \(name)  state=\(data.currentLifecycleState.rawValue)  "
                    + "pinned=\(data.pinned ? "yes" : "no")  "
                    + "views=\(data.viewCount)"
            )
        }
        return lines.joined(separator: "\n")
    }
}
