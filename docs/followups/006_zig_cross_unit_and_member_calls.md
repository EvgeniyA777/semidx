---
title: "Zig cross-unit and member call resolution"
doc_type: "follow_up"
lifecycle: "active"
status: "open"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-09-14"
---

# Zig Cross-Unit And Member Call Resolution

## Classification

`coverage_gap`

## Source

Found in the Plan 004 Stage 4 dogfood run over this repository and recorded as
residual risk.

See
[Plan 004 Stage 4 residual risk](../reports/004_zig_frontend_and_mcp_preview_progress.md#residual-risk)
and [ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md).

## Current Behavior

The Zig frontend resolves only a bare call to the unit's one top-level function
of that name. Everything else stays honest but incomplete:

- Declarations inside containers, such as `Server.handleLine`, are not
  definitions, and their bodies are not walked, so calls made inside methods
  are not recorded.
- Calls through a namespace or a value, such as `protocol.writeString(...)` or
  `self.index.publish()`, are recorded as unresolved `CALLS` with the callee
  text as designator.
- `@import` bindings are not resolved to source units.

As a result `semidx_references` lists only same-unit callers of a Zig function.
In the dogfood run, `semidx_references` for `writeString` in
`src/mcp/protocol.zig` listed its three same-unit callers. Its many calls from
`src/mcp/tools.zig` and `src/mcp/root.zig` are written `protocol.writeString(...)`,
a field-expression callee, and by the frontend's rule are recorded only as
unresolved designators, so none of them was listed.

No false fact is produced: the gap is visible through resolution and
unsupported-construct diagnostics.

## Why Deferred

Plan 005 (preview release readiness) excludes widening language semantics. The
current behavior preserves the fact/unresolved distinction, so it does not
block `v0.1.0-preview.1` as long as the capability matrix and release notes
state it.

Prioritize implementation by dogfood pain after the preview release.

## Acceptance Direction

- Cross-unit Zig resolution is outside ADR 005, which admits only same-unit
  calls. A plan that adds it needs its own decision record.
- ADR 003 forbids repository-wide name matching as graph assertions: a call
  may become a fact only through language-correct resolution, such as an
  `@import` of a relative path to a known unit followed by a public top-level
  declaration of that unit, never by matching the callee's last name segment.
- Container members as definitions and method-call resolution are separate
  steps from cross-unit function calls; each should be scoped explicitly.
- Follow Plan 003's precedent where possible: language vocabulary in extension
  payloads and analyzer projections, without admitting `module` or `IMPORTS`
  unless `CORE.md` admission is completed first.
- Record analysis dependencies on provider units so edits invalidate
  dependents.

## Required Tests

- `const p = @import("protocol.zig"); p.writeString()` resolves to the one
  public top-level function in that unit, with a dependency on it.
- A non-`pub` target, a missing unit, a package import such as
  `@import("std")`, a shadowed binding, and a computed callee stay unresolved
  with explanations.
- An edit that removes or renames the provider's declaration invalidates the
  dependent and leaves the call unresolved rather than stale-as-current.
- If container members become definitions: identity evidence carries the
  container path, a body edit preserves identity, and calls inside members are
  recorded under the same narrow rules.
- `semidx_references` counts a resolved call once and still lists no
  unresolved designator as a caller.
