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
| [006](006_zig_cross_unit_and_member_calls.md) | open | `coverage_gap` | [Plan 004 report](../reports/004_zig_frontend_and_mcp_preview_progress.md#residual-risk) | Zig calls through receivers, values, nested namespaces, container members, and package imports stay unresolved; local-import calls were resolved by Plan 006. |
| [008](008_clojure_lexical_scope_coverage.md) | open | `coverage_gap` | [Plan 005 report](../reports/005_mcp_preview_release_readiness_progress.md#stage-25-same-unit-name-resolution-facts-java-and-clojure) | Clojure symbols under forms that may bind names stay unresolved until lexical scope is modeled. |
| [009](009_mcp_progressive_discovery_and_response_budgets.md) | open | `release_readiness` | [Plan 007 report](../reports/007_mcp_response_budget_and_schema_ergonomics_progress.md#residual-risk) | MCP cold start still needs progressive discovery, compact references, whole-response budgets, and safe continuation. |

## Completed Follow-ups

| ID | Status | Classification | Resolution | Summary |
| --- | --- | --- | --- | --- |
| [004](004_release_discipline_for_mcp_preview.md) | completed | `release_readiness` | [Plan 005](../plans/005_mcp_preview_release_readiness.md) | Preview release discipline, source-built release notes, and release gate were completed for `v0.1.0-preview.1`. |
| [005](005_mcp_source_derived_consent_boundary.md) | completed | `release_readiness` | [Plan 005](../plans/005_mcp_preview_release_readiness.md) | Hosted-client consent wording and default no-source-text evidence were completed for the preview release. |
| [007](007_grammar_setup_fetches_unused_unpinned_sources.md) | fixed | `release_readiness` | [Follow-up 007 resolution](007_grammar_setup_fetches_unused_unpinned_sources.md#resolution) | The grammar setup script fetches only the pinned grammars `build.zig` compiles and checks its list against `build.zig`. |
