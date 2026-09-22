---
title: "Preview adoption measurement progress"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-09-22"
---

# 015: Preview Adoption Measurement Progress

Companion log for
[docs/plans/015_preview_adoption_measurement.md](../plans/015_preview_adoption_measurement.md).

## Current Status

**Stage 0 is prepared, but measurement has not started.** The plan frames the
next work as local evidence collection over `v0.1.0-preview.4`: fallback
visibility in maintained stdio plus real MCP clients, habit-loop runs on two or
three local projects, and an evidence-backed decision about fallback behavior,
proposed ADR 007, roadmap/product strategy, and possible preview.5 UX/tooling
work.

No code or runtime behavior changed in this preparation commit.

## Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Stage 0: Measurement design and project selection | Prepared | Plan created. Project aliases, scenario pack, measurement schema, and privacy rules are specified by the plan, but no projects or clients have been measured yet. |
| Stage 1: Maintained stdio fallback probe | Not started | Wire-level fallback/structured-content measurement remains to implement. |
| Stage 2: Real MCP client output measurement | Not started | Real-client visibility observations remain to collect. |
| Stage 3: Habit-loop runs on real projects | Not started | Two or three project scenario runs remain to collect. |
| Stage 4: Decision and documentation | Not started | Follow-up 010, proposed ADR 007, and product docs must wait for evidence. |
| Stage 5: Optional UX/tooling release slice | Not started | Only active if Stage 4 justifies preview.5. |

## Stage 0: Measurement Design And Project Selection

### Prepared Scope

- Use `v0.1.0-preview.4` as the measured preview.
- Treat source text, private paths, and raw client transcripts as local-only
  unless the operator explicitly provides a public-safe excerpt.
- Commit derived measurements: payload sizes, latency, truncation/budget
  fields, visible client behavior, scenario verdicts, and pain classifications.
- Measure before changing fallback behavior.

### Initial Measurement Schema

| Field | Purpose |
| --- | --- |
| project alias | Stable local label without private absolute paths |
| project kind | Public/private and dominant language mix |
| client | Maintained stdio probe or real MCP client/surface |
| client version | Version when available |
| protocol era | Current stateless or legacy initialized MCP shape |
| scenario | Orientation, lookup, references/context, edit/refresh, or impact |
| tool call | semidx tool name and non-sensitive argument summary |
| structured bytes | Size of `structuredContent` when known |
| fallback bytes | Size of fallback text block when known |
| visible behavior | What the client exposes to the model or UI |
| latency | Observed wall time when measured |
| budget/truncation | Budget fields, cursor, warning, truncation, or spill |
| manual fallback | Whether broad read/grep was still needed |
| pain class | Docs, query shape, response size, client display, setup, or coverage |

### Privacy Rule

Committed evidence may identify this repository directly. For other local
projects, use aliases unless the project is public and the operator explicitly
chooses to name it. Do not commit source snippets, raw transcripts, absolute
paths, credentials, or client logs.

### Verification

| Command | Result |
| --- | --- |
| `git diff --check` | pass |
| `./scripts/check-memory-freshness.sh` | pass |
| `./scripts/check-agent-attribution.sh --all` | pass |

## Next Handoff

Start Stage 1 by adding the smallest repeatable maintained stdio probe for
fallback and structured-content size. Then run Stage 2 against the real MCP
client surfaces available in the local environment before making any fallback
product decision.
