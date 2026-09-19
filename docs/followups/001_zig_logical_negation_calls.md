---
title: "Zig logical negation calls"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-14"
---

# Zig Logical Negation Calls

## Classification

`coverage_gap`

## Source

Found while verifying the Plan 004 Stage 3.5 fix for graph-owned relationship
designators.

See
[Plan 004 progress](../reports/004_zig_frontend_and_mcp_preview_progress.md#stage-35-graph-owned-relationship-designators).

## Current Behavior

The pinned Zig grammar parses a logical negation applied to a call, such as
`!helper()` or `!ns.helper()`, as a `call_expression` whose callee is an
`error_union_type` with source text like `!helper`. The Zig frontend records the
call as unresolved with that designator and does not emit a false `CALLS` fact.

The behavior is honest but incomplete: calls under `!` are undercounted.

## Why Deferred

Plan 004 Stage 4 is the MCP preview. Fixing this while adding MCP would mix a
frontend coverage expansion into a consumer/projection stage.

The current behavior is not a Stage 4 blocker because it preserves the
fact/unresolved distinction.

## Acceptance Direction

A future Zig frontend plan may cover logical-negation callees only after it pins
the exact tree-sitter node shape in a fixture and proves the rewritten callee is
still a normal call target under the frontend's narrow same-unit rule.

Do not add an ad hoc rewrite while implementing MCP.

## Required Tests

- `!foo()` resolves to the same covered same-unit function as `foo()` when no
  shadowing or ambiguity exists.
- `!ns.foo()` remains unresolved; namespace and field resolution stay out of
  scope.
- `!!foo()` has an explicit expected behavior before implementation.
- Error-union type syntax is not mistaken for logical negation of a call.
- Unresolved diagnostics continue to describe the callee shape honestly.
