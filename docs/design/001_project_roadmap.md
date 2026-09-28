---
title: "Project roadmap"
doc_type: "reference"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-28"
---

# Project Roadmap

This roadmap is the orientation layer for semidx. It shows where the project is
going, where it is now, and which direction checks keep it from drifting. It is
not an implementation plan and does not authorize work by itself. Concrete work
still needs a ready plan, ADR, follow-up, or explicit task.

## Product Compass

semidx is a local, incrementally maintained semantic graph of a codebase. The
graph is the authority for semantic entities, relationships, resolution,
freshness, identity, provenance, and diagnostics.

The product is moving toward local tools that let developers and AI agents ask
graph-backed questions about a working copy:

- What entities exist here?
- What defines, contains, references, or calls what?
- Which answers are facts, unresolved assertions, approximate assertions, stale,
  unsupported, or unavailable?
- What changed, and which semantic region should be reanalyzed or inspected?

Consumers such as MCP, CLI, search, IDE integrations, and future retrieval are
projections over the graph. They may shape interfaces, but they must not define
semantic truth.

## Current Position

As of 2026-09-28, the Zig dogfood frontend, its Plan 006 widening, and the
local MCP preview are implemented and reviewed. The local MCP previews
`v0.1.0-preview.1` through `v0.1.0-preview.4` are tagged and pushed to `origin`.
`v0.1.0-preview.4` is the current source-built preview.

On `dev`, [Plan 016](../plans/016_trustworthy_working_copy_sync.md) additionally
delivered content-derived source-state identity, idempotent `semidx_sync`, and
fail-closed read preflight. Every graph read now pays for source discovery;
earlier graph-query timings do not establish current end-to-end MCP latency.
[Plan 015](../plans/015_optional_jev_ranking_projection.md) remains a blocked,
default-off ranking experiment, with no demonstrated ranking usefulness.

Since preview.3, the adoption track advanced through
[Plan 010](../plans/010_java_resolution_boundaries.md) (external Java evidence
and resolution boundaries),
[Plan 011](../plans/011_external_scale_graph_query_indexes.md) (snapshot and
relationship indexes),
[Plan 012](../plans/012_java_semantic_quality_without_query_regression.md)
(class-qualified static calls),
[Plan 013](../plans/013_unresolved_mentions_from_the_callee_anchor.md)
(structured designators and `unresolved_mentions`), and
[Plan 014](../plans/014_java_receiver_coverage.md) (interfaces, declared
supertypes, closed-chain guard relaxation, and covered value receivers). On
apache/dubbo at `df9c5e1`, Plan 013 moved unresolved calls reachable from the
definition they name from 10,141 to 91,087 of 118,471 with facts unchanged, and
Plan 014 converted 1,690 guard-blocked claims plus 3,294 value-receiver calls.

Implemented:

- The architectural constitution, documentation policy, ADR flow, and follow-up
  register are in place.
- The shared in-memory core can represent entities, assertions, facts,
  unresolved targets, stale state, diagnostics, stable identity evidence, and
  published snapshots.
- Repository-scale ingestion can scan trees, preserve source-unit identity,
  reconcile edits, track dependency invalidation, and keep parser-free core
  tests separate from full frontend tests.
- Java and Clojure fixture frontends exist.
- Java same-package top-level type resolution is implemented as the first
  production cross-unit fact, with its classpath limitation tracked separately.
- Plan 004 Stages 1-3 and Stage 3.5 are implemented and reviewed: `.zig`
  source units are discovered, the pinned local Zig grammar builds, top-level
  Zig functions and containers become definitions, same-unit bare Zig calls can
  become exact `CALLS` facts, and graph-owned unresolved designators are fixed.
- Plan 004 Stages 4-5 are implemented and reviewed: `semidx-mcp` serves graph-backed tools
  over stdio to `2026-07-28` and `2025-06-18` clients with source text off by
  default, documented in [the local preview reference](../mcp/local_preview.md).
- [Plan 006](../plans/006_zig_dogfood_semantic_coverage.md) is implemented and
  reviewed ([ADR 006](../adr/006_allow_narrow_zig_member_definitions_and_local_import_calls.md),
  [evidence](../reports/006_zig_dogfood_semantic_coverage_progress.md)): direct
  member functions of top-level Zig containers are definitions, and
  `alias.foo(...)` through a local relative `@import` is an exact cross-unit
  `CALLS` fact with a provider dependency.
- [Plan 009](../plans/009_mcp_progressive_discovery_and_budgets.md) is
  implemented and reviewed on `dev`
  ([evidence](../reports/009_mcp_progressive_discovery_and_budgets_progress.md)):
  MCP discovery now starts with `semidx_outline`, references are compact by
  default, list tools have whole-response budgets, truncation hints, and
  authenticated cursors, and `semidx_context` supports bounded traversal.
- [Plans 010-014](../releases/v0.1.0-preview.4.md) are implemented, reviewed,
  and published in `v0.1.0-preview.4`: Java visibility boundaries, Java-scale
  query indexes, class-qualified static calls, structured designators with
  unresolved mentions, and the Java hierarchy/value-receiver coverage slice.

Tagged (annotated tags, pushed to `origin`):

- `v0.1.0-preview.4` at `e095d95` ([release notes](../releases/v0.1.0-preview.4.md)):
  the preview.3 surface plus Java visibility, Java-scale query indexes,
  class-qualified static calls, structured designators, unresolved mentions,
  declared hierarchy claims, and covered Java value receivers.
- `v0.1.0-preview.3` at `58af737` ([release notes](../releases/v0.1.0-preview.3.md)):
  the preview.2 surface plus Plan 009 progressive MCP discovery, compact
  references, response budgets, narrowing hints, authenticated cursors, and
  bounded traversal.
- `v0.1.0-preview.2` at `8818bb6` ([release notes](../releases/v0.1.0-preview.2.md)):
  the preview.1 surface plus the Plan 006 Zig coverage. The product version was
  raised so the wider behavior is not reported under the preview.1 version.
- `v0.1.0-preview.1` at `e36693a` ([release notes](../releases/v0.1.0-preview.1.md)):
  the Plan 005 handoff, before Plan 006.

Not yet present:

- Stable product release.
- Published semantic contract version or schema set.
- Persistence.
- File watching or daemon lifecycle.
- HTTP transport.
- Source-text MCP output by default.
- General module, import, classpath, namespace, method, or field resolution;
  Zig cross-unit calls beyond local relative `@import` aliases.

## Milestone Ladder

These milestones describe product capabilities, not a mandatory execution order.
The adoption levels below own the current priority order; selected semantic
coverage and memory work need not wait for a stable product or persistence.

| Milestone | Status | Purpose | Exit signal |
| --- | --- | --- | --- |
| M0: Architecture and governance | Done | Freeze product identity and put docs, ADRs, plans, reports, and policies under clear ownership. | Constitution ratified; rules and policy documents active. |
| M1: First semantic graph slice | Done | Prove the model can hold exact entities, relationships, identity, freshness, diagnostics, and snapshots. | Core and full tests pass for Java/Clojure fixtures. |
| M2: Repository-scale local graph | Done | Move from hand-picked files to repository scans and incremental maintenance. | Scan/edit/remove paths preserve consistent graph state and bounded affected-region work. |
| M3: First cross-unit semantic value | Done | Establish one language-correct cross-unit fact without admitting modules/imports prematurely. | Java same-package type references resolve under the narrow rule. |
| M4: Dogfood language and local MCP preview | Done | Make semidx useful to its own development loop and to local agents. | Zig dogfood works; `semidx-mcp` answers graph-backed tools over stdio with source text off by default. |
| M5: Preview release | Done | Make one source-built semidx usable against many local repository roots. | `v0.1.0-preview.1` through `v0.1.0-preview.4` are tagged and pushed, without a stable semantic contract promise. |
| M6: Stable local CLI/MCP product | Later | Stabilize the local user-facing product surface. | `v0.1.0` is cut with documented CLI/MCP behavior, install path, version reporting, and support boundaries. |
| M7: Published semantic contract | Later | Version the semantic model exposed to consumers. | SPEC/CORE publish contract versioning, schema shape, capability matrix, and migration rules. |
| M8: Deeper semantic coverage | Later | Expand exact graph value without collapsing unsupported or unresolved states. | New language or relationship coverage lands through focused plans, ADRs where needed, and conformance evidence. |
| M9: Persistence and continuous operation | Later | Support long-running local use without changing graph authority. | Storage, snapshot representation, refresh/watch behavior, and recovery semantics are specified and tested. |

## Adoption Levels

Levels are an order for investing effort, not release promises or new semantic
contracts. Java is the first external evaluation language because Plans 010-014
already provide a baseline; this does not widen the supported-language roster.
The procedure and numerical evaluation gates belong to
[Plan 017](../plans/017_adoption_baseline_and_priority_selection.md).

| Level | User outcome | Planned work | Exit evidence |
| --- | --- | --- | --- |
| L0: Demonstrate task value | A developer can see when semidx helps and when it does not. | Compare three real tasks with and without semidx on two named external Java repositories; observe two actual MCP clients; run an early memory screen. Plan 017 is the next planned work. | Reproducible task outcomes, complete MCP timings, client-visible output observations, memory history, and one selected next intervention. A negative result is valid evidence. |
| L1: Reduce the cost of obtaining context | Useful current context takes fewer unnecessary calls, reads, and waits. | Fix the largest measured cost in preflight, query work, navigation, or output handling. Measure fallback compatibility before changing it. | Repeat the L0 tasks and demonstrate the improvement chosen in the successor plan, with correctness, freshness, and client compatibility preserved. |
| L2: Recover useful semantic relationships | Ordinary impact questions have useful answers within a clearly stated language boundary. | Select one Java unresolved-reason family by blocked tasks and measured conversion potential; evaluate external-supertype and visibility gaps before admitting new evidence. | Previously blocked task answers become established relationships, with negative cases and provenance verified; raw fact count alone does not pass. |
| L3: Make installation repeatable | A developer gets a first useful answer without knowing the build internals. | Choose initial platforms from evaluation participants; prepare an installation path, actionable diagnostics, and artifacts where justified. | A developer other than the author follows the published path in a clean environment; elapsed time, manual interventions, supported platforms, and failures are recorded. Target: first useful answer within ten minutes, a future acceptance target rather than an observed result. |
| L4: Sustain local sessions | Edits and repository churn do not make a session progressively unusable. | Bound retained memory, verify snapshot lifetimes and recovery; consider continuous operation only from measured need. | Repeated edit/remove/rename histories at bounded live graph size satisfy an explicit memory budget and preserve snapshot validity and identity rules. |

### Ordering And Promotion

- Run L0 first. The memory screen belongs to L0 even though the eventual
  lifecycle work sits in L4.
- Default successor order is L1, L2, L3, then L4. Promote a level when L0
  demonstrates that it blocks completion or adoption more directly than the
  earlier level. Record the evidence and the changed order in `MEMORY.md`.
- A false fact, stale answer presented as synchronized, crash, or reproducible
  memory exhaustion interrupts ordinary feature priority. Capture the smallest
  reproduction and prepare the corrective task before expanding coverage.
- Each implementation successor needs its own ready plan and any required ADR.
  No watcher, metadata shortcut, package manager migration, external type source,
  persistence layer, or new transport is selected by this roadmap.
- Plan 017 ends with a scoped successor plan or an explicit decision that the
  sample shows no justified intervention. It does not silently launch source
  changes or become an indefinite measurement program.

### Inputs And Deferred Work

| Input | Where it enters |
| --- | --- |
| [Plan 016 evidence](../reports/016_trustworthy_working_copy_sync_progress.md) | L0 measures the current complete read path; older query-only timings are historical and not a post-preflight baseline. |
| [010: MCP client output](../followups/010_mcp_text_fallback_client_measurement.md) | L0 observes maintained stdio plus two real clients; L1 may change output only with compatibility evidence. Wire duplication does not prove model-visible duplication. |
| [020: External Java supertype](../followups/020_java_external_supertype_leaves_the_chain_open.md) and [011: Visibility](../followups/011_java_cross_module_visibility.md) | L2 measures the blocked questions and follows each finding's admission requirements; unknown external members are never assumed absent. |
| [017: Reproducible sampling](../followups/017_plan_012_external_evidence_reproducibility.md) | L0 records exact inputs, selection rules, and commands; old aggregate numbers are not silently reused. |
| [006: Zig depth](../followups/006_zig_cross_unit_and_member_calls.md), [001: Negated calls](../followups/001_zig_logical_negation_calls.md), [002: Grammar](../followups/002_zig_empty_container_grammar.md), [008: Clojure scope](../followups/008_clojure_lexical_scope_coverage.md) | Focused follow-ups when observed tasks justify those language investments; no general language expansion in Plan 017. |
| Move-plus-edit identity and snapshot borrowing | L4 and any earlier correctness reproduction; preserve observable identity loss and valid snapshot lifetimes. |

Jev remains blocked under Plan 015's own resume conditions. Ranking, new
languages, HTTP, persistence, and a stable semantic contract are later directions,
not prerequisites for evaluating the current local tool. L4 memory improvements
do not require persistence. Stable contract work remains owned by SPEC/CORE.

## Direction Checks

Before starting a new plan, ask whether it moves at least one of these needles:

- more exact graph knowledge;
- better incremental local operation;
- more useful local projection over published snapshots;
- clearer evidence, contracts, or release discipline.

Stop or re-scope when a proposal:

- turns the graph into a retrieval helper instead of the product;
- lets MCP, CLI, search, or any consumer define semantic truth;
- presents approximate or unresolved knowledge as a fact;
- creates chunk nodes instead of entity nodes;
- requires transmitting source-derived data outside the machine by default;
- widens a language frontend without exact parser or analyzer evidence;
- publishes a stable contract before SPEC/CORE define its lifecycle;
- adds persistence or a daemon before snapshot and refresh semantics are
  specified.

## Open Inputs

Future planning should draw from these current inputs:

- [SPEC.md](../../SPEC.md), especially requirements still to specify.
- [CORE.md](../../CORE.md), especially blocked candidates and publication work.
- [Product adoption strategy](002_product_adoption_strategy.md), especially
  agent habit loops, preview adoption requirements, and release positioning.
- [docs/followups/README.md](../followups/README.md), the accepted deferred
  finding register.
- Active plan progress logs under [docs/reports](../reports/).
