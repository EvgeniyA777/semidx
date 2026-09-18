---
title: "Project roadmap"
doc_type: "reference"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-18"
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

As of 2026-09-18, the Zig dogfood frontend, its Plan 006 widening, and the first
local MCP preview are implemented and reviewed. The local MCP previews
`v0.1.0-preview.1`, `v0.1.0-preview.2`, and `v0.1.0-preview.3` are tagged and
pushed to `origin`. Plan 009's progressive MCP discovery work is published in
`v0.1.0-preview.3`.

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

Tagged (annotated tags, pushed to `origin`):

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

| Milestone | Status | Purpose | Exit signal |
| --- | --- | --- | --- |
| M0: Architecture and governance | Done | Freeze product identity and put docs, ADRs, plans, reports, and policies under clear ownership. | Constitution ratified; rules and policy documents active. |
| M1: First semantic graph slice | Done | Prove the model can hold exact entities, relationships, identity, freshness, diagnostics, and snapshots. | Core and full tests pass for Java/Clojure fixtures. |
| M2: Repository-scale local graph | Done | Move from hand-picked files to repository scans and incremental maintenance. | Scan/edit/remove paths preserve consistent graph state and bounded affected-region work. |
| M3: First cross-unit semantic value | Done | Establish one language-correct cross-unit fact without admitting modules/imports prematurely. | Java same-package type references resolve under the narrow rule. |
| M4: Dogfood language and local MCP preview | Done | Make semidx useful to its own development loop and to local agents. | Zig dogfood works; `semidx-mcp` answers graph-backed tools over stdio with source text off by default. |
| M5: Preview release | Done | Make one source-built semidx usable against many local repository roots. | `v0.1.0-preview.1`, `v0.1.0-preview.2`, and `v0.1.0-preview.3` are tagged and pushed, without a stable semantic contract promise. |
| M6: Stable local CLI/MCP product | Later | Stabilize the local user-facing product surface. | `v0.1.0` is cut with documented CLI/MCP behavior, install path, version reporting, and support boundaries. |
| M7: Published semantic contract | Later | Version the semantic model exposed to consumers. | SPEC/CORE publish contract versioning, schema shape, capability matrix, and migration rules. |
| M8: Deeper semantic coverage | Later | Expand exact graph value without collapsing unsupported or unresolved states. | New language or relationship coverage lands through focused plans, ADRs where needed, and conformance evidence. |
| M9: Persistence and continuous operation | Later | Support long-running local use without changing graph authority. | Storage, snapshot representation, refresh/watch behavior, and recovery semantics are specified and tested. |

## Near-Term Direction

**The adoption track was entered and the first probe is done.**
[Plan 010](../plans/010_java_resolution_boundaries.md) pointed semidx at a Java
repository it does not own — apache/dubbo at `df9c5e1`, 119 Maven modules, 4,050
Java source units — and that is now the project's first non-fixture evidence.
What it showed, in
[its report](../reports/010_java_resolution_boundaries_progress.md):

- Ingestion and incrementality hold at 60 times this repository's size: 4,050
  units in 17.5 s and 290 MB, no unit left unanalyzed, and one edited file
  reanalyzing exactly one unit while preserving entity ids.
- Orientation, definition lookup, and freshness answer their questions well.
- **The impact question does not.** The graph held 336 cross-unit reference
  facts across 26,509 definitions, no cross-unit call facts exist by design, and
  widely used types report no incoming references at all. The adoption strategy
  names that question the strongest adoption signal.
- The false fact Plan 010 was written to remove occurred **zero** times on real
  source. It was latent, not active: ADR 004's other preconditions decline far
  more often than they fire.
- `semidx_context` at `depth=2` cost 90 s on that repository.

The next useful sequence follows from that, not from the plan that preceded it:

1. Decide Java's direction on evidence, not momentum. What limits Java is
   coverage, not boundaries: the supertype guard declined 62% of the unresolved
   references whose target does have source in the working copy, and unresolved
   receivers accounted for 4,624 of 5,662 unresolved calls in the sample. Either
   of those is worth more than any remaining boundary work.
2. Treat per-call latency as product work. A default focused-context tool that
   takes 90 s on a mid-sized repository is not one an agent will keep using, and
   no amount of coverage fixes that.
3. Use the MCP preview while developing semidx itself and collect evidence for
   the next semantic expansion, including how real clients show tool results to
   models ([follow-up 010](../followups/010_mcp_text_fallback_client_measurement.md)).

Current follow-ups should be picked up where they naturally fit:

| Timing | Follow-up | Why then |
| --- | --- | --- |
| Before changing MCP fallback output; useful during or right after the next preview release pass | [010: MCP text fallback client measurement](../followups/010_mcp_text_fallback_client_measurement.md) | The Plan 009 response budget controls structured output, but every result still carries the JSON text fallback. Measure real clients before shortening or configuring it. This does not block publishing the Plan 009 preview unless the release notes need fresh client observations. |
| Next Zig dogfood semantic-coverage plan | [006: Zig cross-unit and member call resolution](../followups/006_zig_cross_unit_and_member_calls.md) | This is the highest-value open semantic gap for semidx's own development: receiver/value calls, nested namespaces, member targets, package imports, and missing-provider invalidation shape day-to-day impact analysis. |
| When the next Zig frontend plan touches callee parsing or call-shape normalization | [001: Zig logical negation calls](../followups/001_zig_logical_negation_calls.md) | Keep it small and parser-evidenced. It is a correctness improvement, but not worth a standalone plan unless the Zig call walker is already open. |
| Parser maintenance or grammar upgrade pass | [002: Zig empty container grammar](../followups/002_zig_empty_container_grammar.md) | First check whether a newer pinned grammar fixes the tree. Until then, the current analysis failure is honest and safer than guessing declarations from an erroneous parse tree. |
| Only with a second language asking a comparable question | [011: Java cross-module visibility](../followups/011_java_cross_module_visibility.md) | Follow-up 003 is closed by [ADR 008](../adr/008_java_visibility_boundaries.md); what remains is recovering cross-module references a build descriptor would permit, worth 1.5% of cross-unit facts on the probed repository. Reading build descriptors badly reintroduces the false fact that was just removed, so this waits for evidence, not appetite. |
| When Clojure becomes an active coverage target | [008: Clojure lexical scope coverage](../followups/008_clojure_lexical_scope_coverage.md) | The current conservative unresolved behavior is correct. Exact lexical scope and known `clojure.core` binding forms are valuable, but only when Clojure coverage is being deliberately expanded. |

After the preview is usable, prioritize work that increases exact graph value
for real local development:

- Zig frontend depth where dogfood shows the highest pain.
- Java coverage where the probe showed it stops — supertypes and receiver calls — rather than further boundary work.
- Source identity evidence for move-plus-edit refactors.
- Capability matrix and public contract lifecycle before promising stable
  consumer semantics.
- Persistence only after the snapshot and contract story is clear.

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
