---
title: "Zig empty container grammar"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-14"
---

# Zig Empty Container Grammar

## Classification

`upstream_limitation`

## Source

Found during Plan 004 Stage 2 while adding top-level Zig container definitions.

See
[Plan 004 progress](../reports/004_zig_frontend_and_mcp_preview_progress.md#stage-2-zig-definition-facts).

## Current Behavior

The pinned `tree-sitter-zig` grammar parses an empty container body such as
`struct {}` or `opaque {}` as a tree with a `MISSING` identifier under a
`container_field`. The frontend treats the whole unit as `analysis_failed` and
does not emit guessed facts.

The `tree-sitter parse` CLI can exit successfully for the same tree, so CLI exit
status is not enough to prove this behavior.

## Why Deferred

Plan 004 deliberately avoids repairing parser trees by assumption. The grammar
bug does not currently affect semidx's own `src/` dogfood set, and the behavior
is pinned by tests as an explicit failure mode.

## Acceptance Direction

A future Zig frontend or parser-maintenance plan should first check whether a
newer grammar commit fixes the parse tree. If it does, bump the pinned grammar
through ADR 002's local-source flow and update the tests.

If the grammar still reports an error, keep the current `analysis_failed`
behavior unless a separate plan proves an exact, parser-evidenced recovery that
does not guess declarations.

## Required Tests

- `const Empty = struct {};`
- `pub const Empty = struct {};`
- `const EmptyOpaque = opaque {};`
- A non-empty container still emits a covered container definition.
- The frontend does not emit facts from a parse tree that still carries errors.
