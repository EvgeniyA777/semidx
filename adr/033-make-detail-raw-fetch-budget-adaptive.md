---
file_type: adr
decision_id: ADR-033
title: Make Detail-Stage Raw Fetch Budget-Adaptive
status: accepted
date: 2026-07-19
deciders:
  - project owner
tags:
  - retrieval
  - budgets
  - contracts
summary: Detail-stage raw-code fetch now degrades the fetch level and slices oversized chunks instead of returning an empty raw_context, and reports a suggested_token_budget plus a raise_token_budget next step when the requested budget was insufficient.
agent_summary: Read this ADR to understand why fetch_context_detail no longer returns empty raw snippets under tight token budgets and how clients should react to suggested_token_budget and the raise_token_budget next step. Treat the Decision and Status sections as normative.
supersedes: []
superseded_by: null
links:
  - reports/015_adaptive_raw_fetch_budget_progress_log.md
---

# ADR-033: Make Detail-Stage Raw Fetch Budget-Adaptive

**Status**: Accepted  
**Date**: 2026-07-19  
**Deciders**: project owner

---

## Context

The detail stage reserves a fixed share of the requested `token_budget` for late
raw-code fetch (10%/20%/70% stage split, then 35% of the detail share for
structure). Before this decision, `perform-raw-fetch` treated each unit chunk as
all-or-nothing: when the first chunk exceeded the byte cap derived from the
remaining budget, the whole fetch loop stopped and `raw_context` came back
empty, with only `raw_fetch_empty` / `raw_fetch_budget_limited` codes and no
indication of how much budget would have been enough.

In observed agent sessions this produced a consistent failure loop: a unit
larger than the default budget returned an empty MCP detail payload, the agent
fell back to reading whole files manually, and the fallback consumed more
tokens than a correctly sized retrieval budget would have.

## Decision Drivers

- retrieval must stay useful under bounded token budgets, not just under
  generous ones
- an empty escalation result is strictly worse than a truncated one for agent
  clients
- clients cannot pick a good `token_budget` without server feedback, because
  only the server knows the selected span sizes
- outputs must remain bounded and contract-valid; the fix must not weaken the
  reserved-budget invariants of the staged flow

## Considered Options

### Option 1. Keep all-or-nothing behavior, document the failure mode

No runtime change; document that clients should retry with a larger budget when
`raw_fetch_empty` appears.

### Option 2. Adaptive degradation, partial slicing, and budget feedback

Degrade the fetch level down the
`whole_file -> local_neighborhood -> enclosing_unit -> target_span` ladder until
the payload fits, slice the front of a still-oversized chunk to the remaining
byte budget instead of dropping it, and report the measured requirement back to
the client as `suggested_token_budget` plus a `raise_token_budget` next step.

### Option 3. Server-side automatic budget raise

Let the detail stage silently exceed the requested `token_budget` when spans
are large.

## Decision

We accept Option 2: adaptive degradation, partial slicing, and budget feedback.

Option 1 leaves the expensive client-side fallback loop in place. Option 3
violates the requested-budget contract: the client asked for a bound and the
server must honor it. Option 2 keeps the bound, maximizes the value delivered
inside it, and gives the client the one number it needs to retry correctly.

Concretely, after this decision:

- `perform-raw-fetch` measures the full token requirement of the requested
  level over the chosen units and returns it as `required_tokens` even when the
  fetch is skipped for lack of budget.
- The fetch level degrades down the ladder until the payload fits the byte cap;
  the effective level is reported honestly (`raw_fetch_level_reached`,
  degradation code `raw_fetch_level_degraded`).
- An oversized chunk is sliced line-by-line from the span start to the
  remaining byte budget instead of being dropped. With a positive raw-fetch
  budget and a readable unit, `raw_context` is never empty.
- When the payload was truncated or degraded, the context-packet budget, the
  diagnostics `budget_summary`, and stage events carry `suggested_token_budget`
  (an inversion of the stage split with a 10% margin), and the detail result
  exposes a top-level `next_step` with `recommended_action "raise_token_budget"`.
- New truncation flags: `raw_snippets_truncated`, `raw_fetch_level_degraded`.
- The zero-detail-budget path (tiny requested budgets where the detail reserve
  is 0) intentionally keeps its previous behavior: raw fetch stays `skipped`
  and `raw_context` stays empty, but `required_tokens` is still measured so the
  suggestion can be emitted.

## Consequences

### Positive

- A single retry with `suggested_token_budget` replaces the manual-file-read
  fallback loop; verified end-to-end (budget 600 on an oversized Python unit
  returns a truncated snippet plus suggestion 6183; the retry returns the full
  span with no truncation flags).
- Truncated-but-present snippets preserve the staged-retrieval value
  proposition under tight budgets.
- The reported fetch level is now always the level that was actually served.

### Negative

- `suggested_token_budget` is a close estimate, not a guarantee: raw need is
  measured over the units kept after structure fitting, so a retry can still
  truncate in rare multi-unit cases and may need one more iteration.
- The byte cap is measured in UTF-8 bytes while token estimates elsewhere use
  characters/4, so suggestions are slightly conservative for non-ASCII content.
- Additive contract surface: `suggested_token_budget` in the context-packet
  budget (JSON Schema + malli mirror) and a top-level `next_step` on the detail
  payload must stay aligned across library, MCP, HTTP, and gRPC surfaces.

### Follow-Up

- Optional: extend `docs/mcp-agent-prompts.md` canonical prompts with an
  explicit "on raise_token_budget, retry once with suggested_token_budget"
  rule for MCP clients.

## Status Changes

None.

## References

- `reports/015_adaptive_raw_fetch_budget_progress_log.md` - implementation and
  verification record
- `reports/011_intent_only_test_retrieval_recall_gap_field_report.md` - earlier
  field observations of budget-related retrieval gaps
- `contracts/schemas/context-packet.schema.json` - budget contract
- `src/semidx/runtime/retrieval.clj` - `perform-raw-fetch`,
  `suggested-token-budget`, `build-detail-response`

## Definition Of Done

`fetch_context_detail` never returns an empty `raw_context` when the raw-fetch
budget is positive and a selected unit is readable; truncated or degraded
detail responses carry `suggested_token_budget` and a `raise_token_budget`
next step; contracts, tests (`test/semidx/runtime/retrieval_test.clj`), and
API reference docs describe the same behavior.
