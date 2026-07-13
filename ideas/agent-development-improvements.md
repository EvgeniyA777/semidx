# Idea: semidx Improvements for Agent-Driven Development

Source: conversation while working on JobApplicationTracker (2026-07-08)

## Context

semidx is currently used as a code exploration tool — finding symbols, tracing call chains, resolving context. But in agent-driven development workflows, there are additional use cases where semidx could provide more value.

---

## Idea 1: Index Non-Code Files (docs, rules, ADRs)

**Problem:** semidx currently indexes Java/Clojure source code. Project rules (`RULES.md`), architecture decision records (`docs/adr/`), and documentation live outside the index. A new agent session has to read these files manually or miss them entirely.

**Idea:** Extend the indexer to include Markdown files — `RULES.md`, `AGENTS.md`, `docs/`, `README.md`. This would allow semantic search like:
> "What are the rules about database configuration?"
> "Is there an ADR about authentication?"

A new agent could orient itself by querying the index instead of reading every file linearly.

---

## Idea 2: Auto-Generate `progress.txt` from `snapshot_diff`

**Problem:** The Clean-Context Restart workflow (Article 1.7) requires manually asking the agent to write a `progress.txt` handoff file. This is error-prone — the agent may omit important things or hallucinate status.

**Idea:** Use `snapshot_diff` to automatically generate a structured handoff file from the diff between two index snapshots (e.g., start of session vs. current state):

```
## Changed since last snapshot
- Added: ApplicationService.filterByStatus()
- Modified: JobApplication entity (added priority field)
- Deleted: none

## Currently broken (compile errors / failing tests)
- ...
```

This would be more reliable than asking the agent to recall what it did.

---

## Idea 3: `impact_analysis` as a Pre-Change Gate

**Problem:** Agents make multi-file changes without understanding ripple effects — touching a shared entity breaks service, controller, and tests in ways not immediately visible.

**Idea:** Make `impact_analysis` a standard step before any multi-file change. The agent calls it, reads the result, and only proceeds if it understands the blast radius. If impact is unexpectedly large — stop and ask the user.

Already added to `RULES.md` in JobApplicationTracker as a convention. Could be enforced via a hook or a pre-change checklist in the agent workflow.

---

## Idea 4: Index Staleness Signal

**Problem:** After a large refactor, the semidx index becomes stale. An agent relying on it gets incorrect symbol locations, outdated call graphs, and wrong impact analysis results.

**Idea:** Expose an index freshness signal — e.g., number of commits since last index build, or a list of files changed since last snapshot. The agent could check this at session start and decide whether to trigger a re-index before proceeding.
