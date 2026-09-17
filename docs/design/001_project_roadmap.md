---
title: "Project roadmap"
doc_type: "reference"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-17"
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

As of 2026-09-17, the Zig dogfood frontend, its Plan 006 widening, and the first
local MCP preview are implemented and reviewed. The local MCP previews
`v0.1.0-preview.1` and `v0.1.0-preview.2` are tagged and pushed to `origin`.

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

Tagged (annotated tags, pushed to `origin`):

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
| M5: Preview release | Done | Make one source-built semidx usable against many local repository roots. | `v0.1.0-preview.1` and `v0.1.0-preview.2` are tagged and pushed, without a stable semantic contract promise. |
| M6: Stable local CLI/MCP product | Later | Stabilize the local user-facing product surface. | `v0.1.0` is cut with documented CLI/MCP behavior, install path, version reporting, and support boundaries. |
| M7: Published semantic contract | Later | Version the semantic model exposed to consumers. | SPEC/CORE publish contract versioning, schema shape, capability matrix, and migration rules. |
| M8: Deeper semantic coverage | Later | Expand exact graph value without collapsing unsupported or unresolved states. | New language or relationship coverage lands through focused plans, ADRs where needed, and conformance evidence. |
| M9: Persistence and continuous operation | Later | Support long-running local use without changing graph authority. | Storage, snapshot representation, refresh/watch behavior, and recovery semantics are specified and tested. |

## Near-Term Direction

The next useful sequence is:

1. Execute [Plan 009](../plans/009_mcp_progressive_discovery_and_budgets.md)
   to make cold-start discovery and references cheaper for agents.
   [Plan 007](../plans/007_mcp_response_budget_and_schema_ergonomics.md) made
   the repository map and context compact by default, and
   [Plan 008](../plans/008_habit_loop_release_gate.md) turned the agent habit
   loop into the `zig build preview-gate` gate
   ([specification](../mcp/habit_loop_gate.md)); its observations are Plan 009's
   baseline.
2. Use the MCP preview while developing semidx itself and collect evidence for
   the next semantic expansion.

After the preview is usable, prioritize work that increases exact graph value
for real local development:

- Zig frontend depth where dogfood shows the highest pain.
- Java classpath/module boundaries before widening Java package facts.
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
