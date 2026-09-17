---
title: "MCP progressive discovery and response budgets"
doc_type: "plan"
lifecycle: "active"
status: "planned"
agent_action: "blocked_until_plan_008_completed"
updated: "2026-09-17"
---

# 009: MCP Progressive Discovery And Response Budgets

## Goal

Make the local MCP preview cheap enough for agent cold start on repositories
larger than the current dogfood tree by changing the navigation strategy, not
only the field detail level.

The intended user value is a progressive path from repository overview to
focused graph facts: an agent should first learn where to look, then request a
small map, then inspect definitions, references, and context with bounded
responses. The preview should remain exact when it knows, honest when it does
not, and local by default.

## Start Rule

Start this plan only after Plan 008 is completed or explicitly superseded.
Plan 008 owns the habit-loop gate and should provide the current output-size
evidence this plan uses for thresholds and regression checks.

If Plan 008 changes the MCP gate command or the response-size observations, use
that evidence here instead of the Plan 007 numbers. If Plan 008 is superseded
without producing gate evidence, the first stage of this plan must recreate the
needed measurements before changing behavior.

## Scope

- Add compact output for `semidx_references`.
- Add progressive repository discovery through a new outline-level MCP surface
  before full repository maps.
- Add truncation guidance that tells callers how to narrow follow-up requests.
- Add whole-response budget discipline that omits whole items and reports
  budget exhaustion without byte-chopping valid JSON.
- Add cursor pagination where it is useful as a safety mechanism for long
  lists, with cursors bound to one snapshot revision.
- Add a bounded lazy graph traversal mode after the one-step context and
  reference surfaces are compact.
- Update tests, dogfood/release-gate evidence, local preview docs, the
  capability matrix, and operational memory.

## Non-Scope

Do not publish a stable semantic contract version, add HTTP, persistence,
resources, prompts, embeddings, a remote service, or source text by default.

Do not make MCP output shape define graph semantics. New outline, cursor,
budget, ranking, hint, or traversal fields are projection behavior only.

Do not implement VCS state filters such as "files changed in Git". A future
graph-native "changed since snapshot revision" feature may be planned
separately if refresh evidence justifies it.

Do not add fuzzy search, BM25, PageRank, or ranked repository maps in this plan.
Ranking is allowed by the architecture as projection behavior, but it should
get its own evidence and tests after progressive disclosure is in place.

Do not add relationship-kind filters to traversal in this plan. Keep traversal
bounded by depth, direction, and response budgets first; add relationship-kind
filtering later if evidence shows it is needed.

Do not change the MCP text fallback policy until client measurements show which
clients need it and which clients expose it to the model.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  sections 1, 3, 5, 7, and 8.
- [SPEC.md](../../SPEC.md), for semantic-contract lifecycle and public-surface
  requirements.
- [Product adoption strategy](../design/002_product_adoption_strategy.md), for
  the agent habit loop and adoption metrics.
- [Local MCP preview](../mcp/local_preview.md), for current tool behavior,
  detail levels, data boundaries, and limits.
- [Preview capability matrix](../spec/capability_matrix.md), for current MCP
  bounds and frontend coverage statements.
- [Plan 007](007_mcp_response_budget_and_schema_ergonomics.md) and
  [Plan 007 progress](../reports/007_mcp_response_budget_and_schema_ergonomics_progress.md),
  for compact detail levels, schema generation, final size observations, and
  residual output risks.
- [Plan 008](008_habit_loop_release_gate.md), for the release-gate evidence
  that must precede this plan.
- [Follow-up 009](../followups/009_mcp_progressive_discovery_and_response_budgets.md),
  for the accepted deferred finding and ordering rationale.

## Current Evidence

Plan 007 established compact defaults for `semidx_repo_map` and
`semidx_context`, with full detail available for focused review. It also
recorded that:

- the compact whole-repository map was still large enough to be a poor default
  first call for larger repositories;
- scoped `path_prefix` maps were much cheaper and more aligned with the
  intended habit loop;
- `semidx_references` rendering was unchanged and still repeated full entities
  in relationships;
- budgets are per list, not per entire response;
- text fallback duplication remains a protocol/client compatibility question.

Plan 008 must refresh these observations through the release gate before this
plan sets hard thresholds.

## Plan-Level Decisions

**Progressive disclosure comes before pagination.** Pagination prevents one
huge response, but it does not make an agent need less information. The first
cold-start surface should be an outline with counts and analysis state, not a
page of a flat full-repository map.

**Compact references are the first implementation win.** References are the
natural next call after definition lookup. They should get the same compact/full
discipline as context before broader discovery work is added.

**Hints are usage guidance, not facts.** A truncation hint may say which
argument to use next. It must not imply that omitted entities are less
important, unrelated, absent, or lower confidence.

**Whole-response budgets select complete values.** The renderer may stop adding
whole files, entities, relationships, diagnostics, or outline entries and report
that it did so. It must never cut JSON, truncate a string to hide meaning, or
make a list look complete when it is not.

**Cursors are snapshot-scoped.** A cursor names a continuation of one tool call
over one snapshot revision and one canonical argument set. After `semidx_refresh`
publishes a different revision, using the old cursor must return a clear tool
error.

**Traversal is explicit and bounded.** `semidx_context` stays one step by
default. Any deeper graph walk must require explicit `depth`, `direction`, and
budget arguments, deduplicate reached entities, and protect against cycles.

## Architecture Boundaries

1. `src/mcp/tools.zig`
Responsibility: tool declarations, argument validation, compact/full rendering,
outline rendering, truncation hints, cursor validation, and budget metadata.
Does not know about: frontend grammar rules or semantic fact creation.

2. `src/mcp/root.zig` and `src/mcp/protocol.zig`
Responsibility: MCP envelopes, error shapes, protocol eras, request dispatch,
and text fallback behavior.
Does not know about: which graph relationships deserve ranking or semantic
priority.

3. `core/Snapshot`
Responsibility: immutable graph queries over one published graph state.
Does not know about: MCP token budgets, cursor strings, client warning
thresholds, or output formatting.

4. Frontends
Responsibility: produce assertions, diagnostics, dependencies, and extension
payloads.
Does not know about: outline grouping, MCP hints, pagination, or response
budgets.

5. Tests and gate evidence
Responsibility: prove bounded behavior, snapshot consistency, honest
truncation, no source-text default, and useful progressive discovery.

## Stages

### Stage 1: Evidence Refresh And Budget Targets

Purpose: turn Plan 008 gate output into thresholds and fixtures for this plan.

Likely files:

- `docs/reports/009_mcp_progressive_discovery_and_budgets_progress.md`
- `tests/mcp_dogfood_test.zig`
- `tests/mcp_stdio_client.zig`
- `docs/mcp/local_preview.md`

Required behavior:

- Record structured and transcript sizes for whole-repository `repo_map`, scoped
  `repo_map`, `semidx_references` for a heavy target, ordinary context, and
  heavy context.
- Record whether the maintained stdio client sees one or two payload copies,
  and record any available real-client warning or file-spill behavior as a
  non-blocking observation.
- Define hard gates only where stable. Prefer shape, completeness, and ratio
  gates over absolute byte counts unless Plan 008 produced a reliable local
  threshold.
- Define a practical default-response target for observations, such as staying
  below the measured client warning zone where possible.

Done when:

- The progress log contains the measured baseline, chosen hard gates, soft
  observations, and any client-specific limits this plan will respect.

### Stage 2: Compact `semidx_references`

Purpose: remove the largest remaining repeated-entity output from the normal
definition-to-impact loop.

Likely files:

- `src/mcp/tools.zig`
- `src/mcp/root.zig`
- `tests/mcp_smoke_test.zig`
- `tests/mcp_dogfood_test.zig`
- `docs/mcp/local_preview.md`
- `docs/spec/capability_matrix.md`

Required behavior:

- Add `detail` (`compact` default, `full`) to `semidx_references`.
- Keep full mode compatible with the current rich rendering, plus `budget`.
- In compact mode, render matched targets once in `targets`; relationships
  should refer to a matched focus target by `id` where possible instead of
  repeating its full entity.
- Preserve relationship `resolution.category`, unresolved designators,
  `producer.name`, `freshness`, evidence path and lines, direction, totals,
  truncation, and target totals.
- Report enough budget metadata to identify `limit`, target limit, detail mode,
  and any whole-response budget applied later.

Done when:

- A `semidx_references` call for the Plan 007 heavy target is materially smaller
  in compact mode while still telling an agent which callers/callees are facts
  and which designators remain unresolved.
- Tests prove that full mode still exposes resolution methods/explanations,
  producer versions, byte offsets, entity extensions, and revisions where the
  previous surface exposed them.

### Stage 3: Truncation Guidance

Purpose: make bounded answers self-correcting for agents.

Likely files:

- `src/mcp/tools.zig`
- `tests/mcp_smoke_test.zig`
- `tests/mcp_dogfood_test.zig`
- `docs/mcp/local_preview.md`

Required behavior:

- Add small structured guidance when a list truncates. Suggested names may be
  `next_hint`, `narrowing_hints`, or a similarly explicit field.
- Hints must name concrete supported arguments, such as `path_prefix`,
  `language`, `path`, `entity_id`, `name`, `direction`, or lower `limit`.
- Hints must be deterministic and generated from the tool shape and arguments,
  not from heuristic judgments about source importance.
- Hints must not appear as graph claims and must not affect query results.

Done when:

- At least one truncating `repo_map`, `references`, and `context` fixture returns
  a useful narrowing hint.
- Non-truncated results do not carry misleading hints.

### Stage 4: Repository Outline

Purpose: replace the flat whole-repository map as the recommended cold-start
orientation call.

Likely files:

- `src/mcp/tools.zig`
- `src/mcp/root.zig`
- `tests/mcp_smoke_test.zig`
- `tests/mcp_dogfood_test.zig`
- `docs/mcp/local_preview.md`
- `docs/spec/capability_matrix.md`
- `MEMORY.md`

Required behavior:

- Add a new outline-level MCP tool named `semidx_outline`.
- The default outline should return immediate children under `path_prefix`:
  directories and files with counts by language, analysis state, diagnostics,
  top-level definitions, and nested definitions, but without listing definition
  entities.
- Include totals and truncation per child list. If directory entries include
  cumulative descendant counts, label them as counts, not as entities.
- Keep paths root-relative and `/`-separated. Do not read source text.
- Make the recommended first-call loop:
  `health -> outline -> repo_map(path_prefix or path) -> find -> references/context`.

Done when:

- The default repository cold-start path can orient an agent without requesting
  every top-level definition in the repository.
- The docs clearly state when to use `semidx_outline` versus `semidx_repo_map`.

### Stage 5: Whole-Response Budget

Purpose: prevent individually bounded lists from combining into one oversized
default response.

Likely files:

- `src/mcp/tools.zig`
- `tests/mcp_smoke_test.zig`
- `tests/mcp_dogfood_test.zig`
- `docs/mcp/local_preview.md`
- `docs/spec/capability_matrix.md`

Required behavior:

- Add a response-level budget mechanism for the tools that can compose multiple
  lists, especially `semidx_context`, `semidx_references`, `semidx_repo_map`,
  and `semidx_outline`.
- The mechanism must choose whole items before rendering, never cut valid JSON,
  and report `budget_exhausted` or an equivalent explicit signal.
- Report omitted totals separately from ordinary per-list truncation where the
  distinction matters.
- Preserve one consistent snapshot per response.
- Keep defaults conservative enough for the Plan 008 habit-loop gate while
  allowing explicit larger limits for local users.

Done when:

- A worst-case multi-focus context fixture cannot exceed the default response
  budget silently.
- Tests prove that budget exhaustion is visible and that no list appears
  complete when omitted items remain.

### Stage 6: Revision-Bound Cursors

Purpose: provide a safe continuation mechanism for long results without making
pagination the main orientation strategy.

Likely files:

- `src/mcp/tools.zig`
- `src/mcp/root.zig`
- `tests/mcp_smoke_test.zig`
- `tests/mcp_dogfood_test.zig`
- `docs/mcp/local_preview.md`

Required behavior:

- Add cursor support only for tools whose result order is deterministic and
  whose continuation semantics are clear.
- Cursor strings are opaque to clients.
- A cursor must encode or otherwise validate the snapshot revision, tool name,
  canonical arguments, and continuation position.
- A cursor from a different snapshot, tool, or argument set returns an explicit
  tool error.
- Cursor pages must preserve existing totals, truncation, budget metadata, and
  no-source-text default behavior.

Done when:

- A large result can be walked in pages without duplicating or skipping items
  within one snapshot.
- A refresh between pages makes the old cursor fail clearly.

### Stage 7: Bounded Graph Traversal

Purpose: let agents walk relevant graph neighborhoods lazily instead of reading
large maps.

Likely files:

- `src/mcp/tools.zig`
- `tests/mcp_smoke_test.zig`
- `tests/mcp_dogfood_test.zig`
- `docs/mcp/local_preview.md`
- `docs/spec/capability_matrix.md`

Required behavior:

- Extend `semidx_context` or add a dedicated traversal tool with explicit
  `depth` (default 1, small maximum), `direction` (`incoming`, `outgoing`,
  `both`), and response-budget controls.
- Render each reached entity once, then refer to repeated nodes by `id`.
- Preserve resolution/freshness/producer on every relationship and keep
  unresolved designators distinct from entity targets.
- Protect against cycles and report traversal truncation or budget exhaustion
  separately from ordinary relationship truncation.
- Keep the one-step default behavior compatible for existing callers.

Done when:

- A fixture with a cycle or repeated neighbor does not repeat full entity
  payloads unboundedly.
- An agent can request a two-step impact neighborhood while still seeing which
  edges are facts and which are unresolved.

### Stage 8: Documentation, Gate Integration, And Handoff

Purpose: make the new navigation strategy the documented agent habit loop.

Likely files:

- `docs/mcp/local_preview.md`
- `docs/spec/capability_matrix.md`
- `docs/reports/009_mcp_progressive_discovery_and_budgets_progress.md`
- `MEMORY.md`
- `docs/followups/009_mcp_progressive_discovery_and_response_budgets.md`

Required behavior:

- Update the first-call sequence to prefer outline before maps.
- Record final size observations and hard-gate results from the habit-loop gate.
- Mark Follow-up 009 closed only if all acceptance directions are satisfied or
  split remaining work into narrower follow-ups.
- Record residual risks: client-specific text fallback behavior, ranking not yet
  implemented, no stable semantic contract, and any remaining large-output
  cases.

Done when:

- A fresh agent can read the preview reference and choose progressive discovery
  without knowing the Plan 007 history.
- The progress log contains verification, review outcome, residual risks, and a
  concise next-step recommendation.

## Verification Strategy

Run:

- `./scripts/check-zig-version.sh`
- `zig fmt --check build.zig src tests`
- `zig build test-mcp`
- `zig build dogfood`
- the Plan 008 habit-loop gate command
- `zig build test` when shared MCP helpers, snapshot query behavior, build
  steps, or core query helpers change

Add focused tests for:

- compact versus full `semidx_references`;
- truncation hints and their absence when not truncated;
- outline counts, ordering, and truncation;
- whole-response budget exhaustion without invalid JSON;
- cursor continuation, stale cursor errors after refresh, and argument mismatch
  errors;
- traversal depth, direction, deduplication, cycle protection, and preservation
  of resolution/freshness/producer.

## Definition Of Done

- The documented cold-start habit loop begins with outline-level progressive
  discovery, not a whole-repository flat map.
- `semidx_references` has compact defaults and full recovery.
- Every large default response path has either a practical budget, truncation
  guidance, cursor continuation, or explicit residual-risk documentation.
- Response budgets omit whole items, preserve valid JSON, and make budget
  exhaustion visible.
- Cursors, if returned, are bound to one snapshot revision and fail clearly
  across refresh.
- Deeper traversal is explicit, bounded, deduplicated, and preserves the
  fact/unresolved/approximate distinction.
- Source text remains absent by default.
- The habit-loop gate records final evidence and passes under the documented
  local prerequisites.
