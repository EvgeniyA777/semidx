---
title: "MCP progressive discovery and response budgets"
doc_type: "follow_up"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-17"
---

# MCP Progressive Discovery And Response Budgets

## Resolution

Completed by [Plan 009](../plans/009_mcp_progressive_discovery_and_budgets.md)
([progress log](../reports/009_mcp_progressive_discovery_and_budgets_progress.md)).
Acceptance directions 1 to 6 are delivered: compact `semidx_references`,
`semidx_outline`, `narrowing_hints`, `max_response_bytes` with
`budget_exhausted`, snapshot-bound cursors, and `semidx_context` traversal with
`direction` and `depth`. Direction 7, text fallback measurement across real
clients, is split into
[Follow-up 010](010_mcp_text_fallback_client_measurement.md). The text below is
the finding as recorded before the plan.

## Classification

`release_readiness`

## Source

Recorded after the Plan 007 post-closure assessment of MCP response budgets.

See
[Plan 007 progress](../reports/007_mcp_response_budget_and_schema_ergonomics_progress.md#post-closure-assessment)
and
[Plan 007 residual risk](../reports/007_mcp_response_budget_and_schema_ergonomics_progress.md#residual-risk).

## Current Behavior

Plan 007 made `semidx_repo_map` and `semidx_context` compact by default, added
`detail: "full"` for recovery of richer fields, made list budgets visible, and
removed schema/validator drift. That materially improved the common agent loop.

The remaining problem is not only field verbosity. The current cold-start
primitive is still mostly flat: a whole-repository `semidx_repo_map` asks for
every indexed source unit and its top-level definitions. Compact rendering
improves the constant factor, but the response still grows with repository
size. In the Plan 007 assessment, the compact whole-repository map over this
repository was still roughly 70 KB structured output, while a scoped
`path_prefix` map for one source directory was much cheaper.

Other output risks remain:

- `semidx_references` still has no compact detail level and can repeat target
  entities in relationships.
- Budgets are per list, not per whole response. A multi-focus `semidx_context`
  can multiply bounded lists into one large message.
- Truncation metadata says what was cut, but does not yet guide the caller
  toward the next narrower request.
- Every tool result still includes structured content plus a JSON text fallback
  for clients without structured-content support. Whether a client exposes one
  or both copies to the model is client-dependent.

## Diagnosis

The primary cold-start issue is the access pattern: "give me the whole map" is
not a scalable first move. More compact fields reduce bytes, but do not change
the shape of exploration.

Progressive disclosure should be the default strategy:

1. Start with repository or directory outline counts.
2. Open a smaller `repo_map` for one path prefix or file.
3. Use exact definition lookup.
4. Ask for compact references or focused context.
5. Request detailed fields only for the one claim or entity that needs review.

Cursor pagination is useful as a safety mechanism for long lists, but it should
not be the primary cold-start strategy. If an agent still needs to read every
page to orient itself, pagination has only moved the cost across calls. A
directory/file outline changes the first question.

VCS-oriented filters such as "files changed" should not be treated as current
semidx behavior. semidx does not model Git state. A graph-native variant such
as "units changed since snapshot revision N" may become useful around refresh
work, but it is a different feature from VCS status.

Exact symbol matching already exists through `semidx_find_definitions`.
Prefix, fuzzy, or ranked candidate search may be useful later as discovery, but
must not establish semantic relationships or present ranked candidates as facts.

## Acceptance Direction

A future implementation plan should prioritize the work in this order:

1. **Compact `semidx_references`.** Reuse the compact rendering discipline from
   `semidx_context`. Since one references query may match up to 50 targets by
   name, render target entities once in `targets`, then refer to them by `id`
   from relationships where possible. Preserve `resolution.category`,
   `producer.name`, `freshness`, location, unresolved designators, totals,
   truncation, and a full detail mode.
2. **Progressive repository outline.** Add a first-call tool or mode, tentatively
   `semidx_outline`, that returns directory and file counts without listing
   every definition. The current `semidx_repo_map` remains the next layer for a
   selected path prefix or file.
3. **Truncation guidance.** When a result truncates, include a small structured
   hint that tells the caller which argument can narrow the next request, such
   as `path_prefix`, `language`, `path`, `entity_id`, or a lower limit. Hints are
   tool-usage guidance, not graph facts.
4. **Whole-response budget.** Keep valid JSON and omit only whole items, but add
   a response-level budget signal such as `budget_exhausted` when rendering
   stops before all bounded lists are filled. Default responses should aim to
   stay below practical agent-client warning zones where this can be measured
   reliably.
5. **Revision-bound cursors.** Use cursor pagination only as a fallback for long
   result sets. Cursors must be opaque and tied to the snapshot revision and the
   canonical tool arguments. A cursor from an older snapshot must fail
   explicitly after refresh rather than mixing graph states.
6. **Lazy graph traversal.** Extend focused context navigation with explicit
   `depth` and `direction` only after the one-step surfaces are compact. Render
   each reached node once and refer to already-seen nodes by `id` to avoid
   repeated entity payloads and cycles.
7. **Text fallback measurement.** Measure at least the maintained stdio client
   and one or more real MCP clients before changing or shortening the text
   fallback. The protocol/client compatibility cost is separate from semantic
   output budgeting.

## Architectural Constraints

- MCP remains a projection/consumer. It may shape output, budgets, hints, and
  cursors, but must not define graph semantics.
- Unresolved, approximate, stale, unsupported, unavailable, and confirmed
  absence signals must remain distinguishable on every surface that returns
  those claims.
- Ranked, fuzzy, or budget-selected output may order or omit candidates, but it
  must not create relationships or promote candidates to facts.
- Every response must observe one snapshot. Cursors and multi-call traversal
  must make snapshot revision boundaries explicit.
- No implementation may require a remote service or return source text by
  default.

## Evidence Needed Before Implementation

Plan 008 should provide fresh gate evidence before this follow-up becomes an
implementation plan:

- structured and transcript sizes for whole-repository `repo_map`;
- the same sizes for `repo_map` scoped by representative `path_prefix` values;
- `semidx_references` size for a high-fan-in or repeated-target case;
- compact and full `semidx_context` sizes for one ordinary and one heavy target;
- which client-visible result size crosses practical warning or file-spill
  thresholds, if the client reports them;
- whether text fallback duplication is visible to the model in the tested
  client.

## Closure Direction

Close this follow-up when a completed plan has delivered progressive discovery
and response-budget controls sufficient for the local preview habit loop, with
the remaining large-output cases recorded as explicit residual risk or split
into narrower follow-ups.
