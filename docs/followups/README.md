# Follow-up Register

Concrete deferred findings live here when they are worth preserving as inputs
for future plans but are not themselves implementation plans.

Use this register for accepted deferred defects, coverage gaps, semantic
limitations, upstream limitations, and process defects. Do not use it as a broad
wishlist: each entry should name current behavior, why it was deferred, and what
evidence would make it ready to implement or close.

## Classification

- `bug`: behavior known to be wrong.
- `coverage_gap`: honest but incomplete semantic coverage.
- `semantic_limitation`: exact current behavior with a known boundary that can
  produce incomplete or overbroad answers.
- `upstream_limitation`: behavior blocked or distorted by an external parser or
  tool source.
- `process_defect`: project workflow or verification behavior that let a defect
  through or made evidence ambiguous.
- `release_readiness`: packaging, versioning, distribution, or release-gate work
  needed before publishing an installable product.

## Open Follow-ups

| ID | Status | Classification | Source | Summary |
| --- | --- | --- | --- | --- |
| [001](001_zig_logical_negation_calls.md) | open | `coverage_gap` | [Plan 004 report](../reports/004_zig_frontend_and_mcp_preview_progress.md#stage-35-graph-owned-relationship-designators) | Zig calls under logical negation stay unresolved as `!callee`. |
| [002](002_zig_empty_container_grammar.md) | open | `upstream_limitation` | [Plan 004 report](../reports/004_zig_frontend_and_mcp_preview_progress.md#stage-2-zig-definition-facts) | The pinned Zig grammar reports empty container bodies as parse errors. |
| [003](003_java_classpath_boundaries.md) | open | `semantic_limitation` | [Plan 003 report](../reports/003_java_package_type_resolution_progress.md#residual-risk) | Java same-package resolution treats the repository as one classpath. |
| [004](004_release_discipline_for_mcp_preview.md) | open | `release_readiness` | [Plan 004](../plans/004_zig_frontend_and_mcp_preview.md#stage-5-dogfood-documentation-and-handoff) | Define preview and stable release rules for the local CLI/MCP product. |
| [005](005_mcp_source_derived_consent_boundary.md) | open | `release_readiness` | [Plan 004 final review](../reports/004_zig_frontend_and_mcp_preview_progress.md#final-review) | Define hosted-client consent wording for source-derived MCP graph values. |
