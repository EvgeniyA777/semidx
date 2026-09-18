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
| [006](006_zig_cross_unit_and_member_calls.md) | open | `coverage_gap` | [Plan 004 report](../reports/004_zig_frontend_and_mcp_preview_progress.md#residual-risk) | Zig calls through receivers, values, nested namespaces, container members, and package imports stay unresolved; local-import calls were resolved by Plan 006. |
| [008](008_clojure_lexical_scope_coverage.md) | open | `coverage_gap` | [Plan 005 report](../reports/005_mcp_preview_release_readiness_progress.md#stage-25-same-unit-name-resolution-facts-java-and-clojure) | Clojure symbols under forms that may bind names stay unresolved until lexical scope is modeled. |
| [010](010_mcp_text_fallback_client_measurement.md) | open | `release_readiness` | [Plan 009 report](../reports/009_mcp_progressive_discovery_and_budgets_progress.md#payload-copies) | Measure how real MCP clients expose the duplicated text fallback before changing it. |
| [011](011_java_cross_module_visibility.md) | open | `coverage_gap` | [Plan 010 report](../reports/010_java_resolution_boundaries_progress.md) | Java cross-module same-package references stay unresolved, because no build descriptor is read. |

## Completed Follow-ups

| ID | Status | Classification | Resolution | Summary |
| --- | --- | --- | --- | --- |
| [004](004_release_discipline_for_mcp_preview.md) | completed | `release_readiness` | [Plan 005](../plans/005_mcp_preview_release_readiness.md) | Preview release discipline, source-built release notes, and release gate were completed for `v0.1.0-preview.1`. |
| [005](005_mcp_source_derived_consent_boundary.md) | completed | `release_readiness` | [Plan 005](../plans/005_mcp_preview_release_readiness.md) | Hosted-client consent wording and default no-source-text evidence were completed for the preview release. |
| [009](009_mcp_progressive_discovery_and_response_budgets.md) | completed | `release_readiness` | [Plan 009](../plans/009_mcp_progressive_discovery_and_budgets.md) | Outline, compact references, truncation hints, whole-response budgets, snapshot-bound cursors, and bounded traversal were delivered; text fallback measurement split into 010. |
| [003](003_java_classpath_boundaries.md) | completed | `semantic_limitation` | [ADR 008](../adr/008_java_visibility_boundaries.md), [Plan 010](../plans/010_java_resolution_boundaries.md) | Java visibility is now the derived source root; the cross-module part is split into 011. |
| [007](007_grammar_setup_fetches_unused_unpinned_sources.md) | fixed | `release_readiness` | [Follow-up 007 resolution](007_grammar_setup_fetches_unused_unpinned_sources.md#resolution) | The grammar setup script fetches only the pinned grammars `build.zig` compiles and checks its list against `build.zig`. |
