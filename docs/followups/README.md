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
- `performance_gap`: exact current behavior whose physical access path or
  runtime cost blocks expected product use at measured scale.
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
| [013](013_java_supertype_guard_relaxation.md) | open | `coverage_gap` | [Plan 012 report](../reports/012_java_semantic_quality_without_query_regression_progress.md#supertype-guard-opportunity) | A class with supertypes resolves no simple type name beyond its unit; lifting the guard safely needs a hierarchy closed in indexed source, which 13 of 335 measured cases have. |
| [014](014_java_instance_receiver_calls.md) | open | `coverage_gap` | [Plan 012 report](../reports/012_java_semantic_quality_without_query_regression_progress.md#the-addressable-receiver-subset) | Calls through a value receiver stay unresolved; the type environment they need was measured at 63 exact facts and declined by Plan 012's gate. |
| [017](017_plan_012_external_evidence_reproducibility.md) | open | `process_defect` | [Plan 012 review](../reports/012_java_semantic_quality_without_query_regression_progress.md#post-closure-review-2026-09-20) | `zig build claim-sample` now draws a sample reproducible from its seed alone and reports any unclassified reason, but Plan 012's own numbers were drawn by a selection nobody kept, so they stay unverifiable until a new baseline is measured on a clone. |
| [018](018_unexplained_assertion_delta.md) | open | `process_defect` | [Plan 012 Stage 6](../reports/012_java_semantic_quality_without_query_regression_progress.md#one-delta-this-stage-did-not-explain) | 106 assertion records appeared that were not conversions of existing ones; it does not show at module scale, so it is tied to batch-wide reanalysis rather than to the resolution rule. |
| [019](019_designator_may_carry_source_expression.md) | open | `bug` | [Plan 013 readiness review](../plans/013_unresolved_mentions_from_the_callee_anchor.md) | A Java designator holds the whole invocation text and renders with no opt-in, so expression text reaches default MCP output against the boundary three documents state; Plan 013 D1, D10 and D11 close it. |

## Completed Follow-ups

| ID | Status | Classification | Resolution | Summary |
| --- | --- | --- | --- | --- |
| [012](012_external_scale_query_latency.md) | completed | `performance_gap` | [Plan 011](../plans/011_external_scale_graph_query_indexes.md) | Snapshot identity lookups and anchored relationship queries are indexed projections of the snapshot's own assertions; a work bound at 244,559 assertions replaced the proposed latency gate, and the Java write path was measured and left unchanged. |
| [004](004_release_discipline_for_mcp_preview.md) | completed | `release_readiness` | [Plan 005](../plans/005_mcp_preview_release_readiness.md) | Preview release discipline, source-built release notes, and release gate were completed for `v0.1.0-preview.1`. |
| [005](005_mcp_source_derived_consent_boundary.md) | completed | `release_readiness` | [Plan 005](../plans/005_mcp_preview_release_readiness.md) | Hosted-client consent wording and default no-source-text evidence were completed for the preview release. |
| [009](009_mcp_progressive_discovery_and_response_budgets.md) | completed | `release_readiness` | [Plan 009](../plans/009_mcp_progressive_discovery_and_budgets.md) | Outline, compact references, truncation hints, whole-response budgets, snapshot-bound cursors, and bounded traversal were delivered; text fallback measurement split into 010. |
| [003](003_java_classpath_boundaries.md) | completed | `semantic_limitation` | [ADR 008](../adr/008_java_visibility_boundaries.md), [Plan 010](../plans/010_java_resolution_boundaries.md) | Java visibility is now the derived source root; the cross-module part is split into 011. |
| [015](015_unit_path_change_does_not_reanalyze.md) | fixed | `bug` | [Follow-up 015 resolution](015_unit_path_change_does_not_reanalyze.md#resolution) | A unit that moves to another directory is reanalyzed and marks everything it exposes as changed, so a cross-unit fact no longer survives a visibility boundary the reader can no longer cross. |
| [016](016_java_static_call_rule_narrow_gaps.md) | fixed | `bug` | [Follow-up 016 resolution](016_java_static_call_rule_narrow_gaps.md#resolution) | An on-demand static import now declines every simple-name receiver, a missing `java.static` label reads back as unrecorded, and the two unreachable declines are pinned by a lookup-order test. |
| [007](007_grammar_setup_fetches_unused_unpinned_sources.md) | fixed | `release_readiness` | [Follow-up 007 resolution](007_grammar_setup_fetches_unused_unpinned_sources.md#resolution) | The grammar setup script fetches only the pinned grammars `build.zig` compiles and checks its list against `build.zig`. |
