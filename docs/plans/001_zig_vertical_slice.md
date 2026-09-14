---
title: "Zig semantic graph vertical slice"
doc_type: "plan"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-13"
---

# 001: Zig Semantic Graph Vertical Slice

**Executed and closed on 2026-09-13.** Every stage below is implemented and
verified; the outcomes, evidence, limitations, and residual risk are in
[docs/reports/001_zig_vertical_slice_progress.md](../reports/001_zig_vertical_slice_progress.md).
This document is kept as the record of what was planned, not as a work queue.

## Goal

Implement the first `semidx` vertical slice in Zig, proving that the rebuilt
core can model semantic entities, exact and unresolved assertions, basic
relationships, and incremental identity-preserving reconciliation across small
Java and Clojure fixtures.

This plan operationalizes [ADR 001](../adr/001_choose_zig_implementation_language.md).
Its companion progress log is
[docs/reports/001_zig_vertical_slice_progress.md](../reports/001_zig_vertical_slice_progress.md).

## Scope

Build a local, in-memory Zig implementation that can:

- ingest small Java and Clojure source fixtures;
- run language frontends through a parser dependency boundary;
- emit semantic entities, `DEFINES`, `REFERENCES`, and `CALLS` assertions;
- record provenance and resolution for every assertion;
- distinguish facts from unresolved assertions;
- encode approximate assertions as a category even if the slice does not
  produce them;
- build and query an in-memory graph snapshot;
- apply a source edit to an existing graph;
- reconcile the affected region incrementally;
- preserve identity for unchanged entities when correspondence is established;
- expose identity loss when correspondence is not established;
- verify all of the above through deterministic local tests.

## Non-Scope

Do not implement persistence, MCP, HTTP, vectors, RAG, embeddings, concurrency,
daemon mode, background file watching, repository-scale indexing, public schemas,
contract version publication, IDE integration, or performance optimization
beyond simple local budgets that prevent accidental pathological behavior.

Do not claim published Java or Clojure support. Fixture coverage in this plan is
conformance evidence for the first slice, not a supported language roster.

Do not admit new core kinds in `CORE.md` as part of this implementation unless a
separate requirements change explicitly accepts the admission evidence. The
slice may exercise current candidates as internal draft semantics.

## Assumptions

- Zig remains the implementation language under
  [ADR 001](../adr/001_choose_zig_implementation_language.md).
- The first implementation may introduce `build.zig`, `src/`, `fixtures/`, and
  test files; those paths do not exist at plan creation time.
- Zig's standard build system is sufficient for the first slice.
- Parser integration should use local tree-sitter grammar sources through the C
  ABI. Runtime indexing must not require network access.
- If grammar sources or Zig toolchain setup are unavailable locally, execution
  stops at the dependency stage and records the exact blocker in the progress
  log. Do not replace parser integration with ad hoc regex parsing to bypass the
  blocker.
- The slice may use a simple deterministic fixture-query output for tests. That
  output is not a public contract.

## Source Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md) owns the
  non-negotiable architecture: graph authority, entity nodes, knowledge
  categories, stable identity, incrementality, language frontends, consumer
  independence, and local operation.
- [ADR 001](../adr/001_choose_zig_implementation_language.md) owns the Zig
  language decision and the first-slice intent.
- [SPEC.md](../../SPEC.md) owns changing requirements, core lifecycle, coverage,
  and conformance expectations.
- [CORE.md](../../CORE.md) owns draft candidate kinds and relationships.
- [CONFORMANCE.md](../../CONFORMANCE.md) owns scenario families.
- [MEMORY.md](../../MEMORY.md) owns current implementation reality.

## Plan-Level Decisions

- Use Zig's standard build system: `build.zig`, `zig build`, and
  `zig build test`.
- Keep parser dependencies local and explicit. Prefer vendored or locally
  generated tree-sitter C sources under a clearly named dependency directory.
- Keep the semantic graph in memory only.
- Use deterministic tests as the primary surface. A small developer-only CLI may
  be added only if it makes fixture inspection or runtime smoke checks clearer.
- Keep language-specific constructs in frontend extension payloads. The shared
  core sees only source containers, definitions, relationships, assertion
  provenance, resolution, evidence, and identity correspondence.
- Model source ranges as evidence/projections, never as entity identity.

## Architecture Plan

### Boundaries

1. `core/model`
Responsibility: entity, relationship, assertion, provenance, resolution, source
evidence, and identity correspondence data structures.
Knows about: constitutional semantic terms and draft core candidates.
Does not know about: parser APIs, Java syntax, Clojure syntax, filesystem
walking, CLI formatting, persistence, or public protocols.
Why this boundary exists: the shared model must not be defined by one frontend
or by an external parser.

2. `core/graph`
Responsibility: in-memory graph construction, snapshot storage, deterministic
queries for tests, assertion insertion rules, and invariant checks.
Knows about: `core/model` values and graph-level validation.
Does not know about: how a frontend parsed a source file or how a future
consumer wants results formatted.
Why this boundary exists: graph authority and knowledge-category separation
must be testable without parser dependencies.

3. `frontend/contract`
Responsibility: the narrow contract by which language frontends contribute
assertions to the shared model.
Knows about: source units, frontend capabilities, frontend batches, diagnostics,
and extension payload envelopes.
Does not know about: graph storage internals or reconciliation policy.
Why this boundary exists: Java, Clojure, and later frontends must be
substitutable without redefining the core.

4. `frontends/java`
Responsibility: fixture-scoped Java extraction for classes or methods/functions
chosen by the fixture, direct containment, simple references, simple calls, and
unresolved references.
Knows about: Java tree-sitter parse nodes and Java-specific extension labels.
Does not know about: Clojure semantics, graph identity allocation, or public
query surfaces.
Why this boundary exists: Java-specific constructs must remain extension
details.

5. `frontends/clojure`
Responsibility: fixture-scoped Clojure extraction for namespaces/forms/defs
chosen by the fixture, direct containment, simple references, simple calls, and
unresolved references.
Knows about: Clojure tree-sitter parse nodes and Clojure-specific extension
labels.
Does not know about: Java semantics, graph identity allocation, or public query
surfaces.
Why this boundary exists: Clojure macros, vars, and namespace forms must not
flatten the shared core into Clojure-specific meaning.

6. `reconcile`
Responsibility: apply a changed frontend batch to an existing graph snapshot,
match entities using identity evidence, preserve established identities, replace
affected assertions, and report identity breaks.
Knows about: graph snapshots, source units, frontend batches, and identity
evidence.
Does not know about: parser internals or future persistence mechanics.
Why this boundary exists: stable identity and incrementality are core behavior,
not parser behavior.

7. `fixtures`
Responsibility: small Java and Clojure source examples, edit histories, and
expected semantic outcomes for tests.
Knows about: fixture source text and expected graph assertions.
Does not know about: production repository layouts or public API schemas.
Why this boundary exists: the first slice needs executable evidence without
claiming language support beyond its fixtures.

### Contracts

1. `FrontendInput`
Client: language frontend implementations.
Shape: source unit id, path, language tag, source bytes, and optional previous
parse metadata if the parser supports incremental parsing.
Variation strategy: direct Zig struct owned by `frontend/contract`.

2. `FrontendBatch`
Client: graph builder and reconciler.
Shape: extracted entities, relationship assertions, unresolved assertions,
source evidence, diagnostics, frontend capability metadata, and language
extension payloads.
Variation strategy: composition; each frontend fills the same batch shape and
keeps language-specific data inside extension envelopes.

3. `AssertionResolution`
Client: graph invariant checks and tests.
Shape: `fact`, `unresolved`, and `approximate` categories with producer,
evidence, and explanation fields sufficient to distinguish how far the claim is
resolved.
Variation strategy: closed enum for the slice; future extension requires a
requirements update because consumers rely on this distinction.

4. `IdentityEvidence`
Client: reconciler.
Shape: source scope, language tag, frontend entity role, stable name/signature
when available, containment context, and source evidence. It is evidence for
correspondence, not the entity id itself.
Variation strategy: direct struct with frontend-specific extension data allowed
only as evidence.

5. `GraphSnapshot`
Client: tests and optional developer CLI.
Shape: immutable observable state containing entities, assertions, diagnostics,
and identity events after a build or reconciliation step.
Variation strategy: direct in-memory value for the slice. Persistence is not a
participant.

### Dependency Direction

- Core model and graph policy depend only on Zig standard library types and
  internal value contracts.
- Reconciliation depends on the graph model and frontend batches.
- Java and Clojure frontends depend on parser adapters and the frontend
  contract.
- Parser adapters depend on tree-sitter C APIs and grammar bindings.
- Tests depend on all implementation modules and fixture data.
- No core module depends on CLI output, parser node types, persistence, network
  services, or public protocol vocabulary.

## Implementation Sequence

### Stage 1: Zig Scaffold And Dependency Probe

Purpose: create the smallest buildable Zig project and prove the local toolchain
boundary before semantic code depends on it.

Planned files:

- `build.zig`
- `src/main.zig` or `src/lib.zig`
- `src/core/`
- `src/frontend/`
- `src/frontends/`
- `src/reconcile/`
- `fixtures/vertical-slice/`

Tasks:

- Check and record `zig version`.
- Create `build.zig` with `zig build test`.
- Add a trivial unit test.
- Probe tree-sitter C API and local Java/Clojure grammar availability.
- Choose and document the exact dependency location used by the slice.

DoD:

- `zig build test` passes for the scaffold.
- Progress log records Zig version, parser dependency state, and any local
  setup limitation.
- If parser dependencies are missing, stop before frontend implementation and
  record the exact install or vendoring decision needed.

### Stage 2: Core Semantic Model

Purpose: encode the constitutional distinctions before parser-specific work
begins.

Tasks:

- Define entity, relationship, assertion, resolution, provenance, source
  evidence, and identity correspondence types.
- Encode `repository`, `file`, `definition`, `DEFINES`, `REFERENCES`, and
  `CALLS` as draft slice semantics aligned with `CORE.md`.
- Add constructors or validation functions that reject assertions without
  producer and resolution metadata.
- Add tests for fact, unresolved, and approximate categories, even if
  approximate values are not produced by frontends yet.

DoD:

- Unit tests prove that facts and unresolved assertions cannot be confused.
- Unit tests prove that source ranges are evidence/projection data, not entity
  ids.
- No parser or frontend dependency is required to test `core/model`.

### Stage 3: In-Memory Graph And Query Harness

Purpose: make the graph the semantic authority for the slice.

Tasks:

- Implement graph snapshot construction from validated assertions.
- Add deterministic query helpers for tests: entities by kind, relationships by
  kind, unresolved assertion count, and identity events.
- Add graph invariants for duplicate ids, missing endpoints, invalid assertion
  resolution, and relationship provenance.
- Add an optional developer-only command that prints fixture graph summaries if
  it improves runtime smoke evidence.

DoD:

- Unit tests build a graph without any language frontend.
- Invalid graph inputs fail with explicit diagnostics.
- Query helpers return graph-derived semantic answers only.

### Stage 4: Frontend Contract And Parser Adapter

Purpose: keep parser details at the edge while proving real dependency
integration.

Tasks:

- Define `FrontendInput`, `FrontendBatch`, diagnostics, capabilities, and
  extension payload envelopes.
- Implement the tree-sitter adapter boundary needed by both frontends.
- Add parser smoke tests for one tiny Java fixture and one tiny Clojure fixture.
- Ensure parser failure produces an unavailable-analysis diagnostic, not an empty
  semantic result that looks like confirmed absence.

DoD:

- Focused integration tests parse both fixture languages locally.
- Parser node details do not appear in `core/model` or `core/graph`.
- Missing or failed parser input is distinguishable from "no entities found".

### Stage 5: Java Fixture Frontend

Purpose: extract fixture-scoped Java assertions without letting Java define the
shared core.

Fixture coverage:

- one file source container;
- one or more Java definitions;
- direct `DEFINES` containment;
- one resolved `REFERENCES`;
- one resolved `CALLS`;
- one unresolved reference or call target;
- Java extension labels for constructs the shared core does not own.

Tasks:

- Add Java fixture source and expected semantic outcome.
- Implement Java frontend extraction for only the fixture coverage.
- Emit provenance and source evidence for every assertion.
- Emit unresolved assertions for supported references whose target cannot be
  resolved inside the fixture scope.

DoD:

- Fixture/golden tests pass for Java entities and relationships.
- The same occurrence is not double-counted when a `CALLS` assertion also
  satisfies a reference query expectation.
- Unsupported Java constructs are reported as unavailable or out of coverage
  where the fixture requires that distinction.

### Stage 6: Clojure Fixture Frontend

Purpose: force the shared core to survive a second language family early.

Fixture coverage:

- one file source container;
- one or more Clojure definitions;
- direct `DEFINES` containment;
- one resolved `REFERENCES`;
- one resolved `CALLS`;
- one unresolved reference or call target;
- Clojure extension labels for constructs the shared core does not own.

Tasks:

- Add Clojure fixture source and expected semantic outcome.
- Implement Clojure frontend extraction for only the fixture coverage.
- Keep Clojure namespace, var, macro, and form-specific meaning in extension
  payloads unless the draft core already owns the meaning.
- Emit unresolved assertions for supported references whose target cannot be
  resolved inside the fixture scope.

DoD:

- Fixture/golden tests pass for Clojure entities and relationships.
- Clojure-specific semantics do not appear as new shared-core kinds.
- Unsupported or unavailable analysis remains distinguishable from confirmed
  absence.

### Stage 7: Incremental Reconciliation

Purpose: prove that identity and incrementality are first-slice behavior, not
later infrastructure.

Edit scenarios:

- edit a function or method body without changing the entity correspondence;
- add an unrelated definition;
- remove or rename a definition in a way that produces observable identity loss
  or replacement;
- change a reference target from unresolved to resolved or resolved to
  unresolved.

Tasks:

- Represent a source edit as a changed source unit plus previous graph snapshot.
- Re-run the affected frontend only for the changed unit.
- Match new entities against previous entities using identity evidence.
- Preserve entity ids when correspondence is established.
- Replace assertions for the affected region and keep unrelated graph state
  stable.
- Record identity events for preserved, created, removed, and lost
  correspondence cases.

DoD:

- Fixture/golden tests prove identity preservation after body-only edits.
- Tests prove unrelated entities keep ids and assertions.
- Tests prove identity loss is observable instead of hidden as silent delete and
  create.
- Reconciliation tests operate on an existing graph snapshot, not by discarding
  all state and pretending a rebuild was incremental.

### Stage 8: Slice Closure And Documentation

Purpose: leave the repository in a coherent state after the first working slice.

Tasks:

- Update `MEMORY.md` with actual implementation reality, build commands,
  dependency assumptions, known limitations, and next priorities.
- Update `SPEC.md`, `CORE.md`, or `CONFORMANCE.md` only if the implementation
  creates new requirement facts or accepted evidence that those documents own.
- Update the progress log with completed stages, exact verification commands,
  skipped checks, review findings, and residual risk.
- Run the narrow meaningful checks first, then the documented slice lane.
- Commit the completed slice.

DoD:

- `zig build test` passes.
- Parser/frontend fixture tests pass locally.
- Progress log records all stage outcomes and any skipped checks.
- Documentation describes implemented behavior without claiming published
  contracts or broad language support.
- Working tree is clean after the final commit.

## Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Zig stack builds locally | Implementation cannot run on a clean local checkout | Runtime smoke | `zig build test` from repository root | Missing Zig or unsupported Zig version | Stage 1 command evidence |
| Parser dependencies integrate cleanly | Frontends are forced into ad hoc parsing or parser details leak into core | Focused integration | Java and Clojure parser smoke tests through adapter | Missing grammar, parse error, unavailable parser | Stage 4 parser tests and diagnostics |
| Nodes represent entities | Source ranges or chunks become graph identity | Unit plus fixture/golden | Entity ids allocated from semantic correspondence, ranges stored as evidence | Whitespace reflow or range movement | Stage 2 and Stage 7 tests |
| Facts and unresolved assertions stay distinct | Unresolved targets appear as exact facts | Unit plus fixture/golden | Assertion constructors and graph invariant checks | Unresolved call/reference target | Stage 2, Stage 5, Stage 6 tests |
| `CALLS` does not flatten language semantics | Java or Clojure invocation details become shared-core meaning | Fixture/golden | Extension payloads retain language-specific labels | Macro/protocol/dispatch detail outside fixture coverage | Stage 5 and Stage 6 expected outputs |
| Graph is the semantic authority | Test answers come from frontend output or CLI formatting instead of graph | Unit plus integration | Query helpers read graph snapshot only | Direct frontend batch queried as result | Stage 3 tests |
| Incremental reconciliation preserves identity | Body edits delete and recreate unchanged entities | Fixture/golden | Existing graph snapshot reconciled with changed batch | Body-only edit, move/reorder, rename/loss case | Stage 7 edit-history tests |
| Unavailable analysis is honest | Parser or unsupported construct failures look like empty results | Focused integration | Diagnostics carry unavailable/failure status | Parser failure, unsupported construct | Stage 4-6 negative tests |
| Local operation and privacy | Runtime depends on service or network | Runtime smoke | Build and tests run without required service | Network unavailable, no daemon running | Stage 1 and Stage 8 command evidence |
| Documentation stays truthful | Docs claim published coverage or contracts too early | Documentation review | Links to ADR/SPEC/CORE/CONFORMANCE and explicit limitations | Broad Java/Clojure support wording | Stage 8 diff review |

## Plan Readiness Gate

This plan is ready for implementation when:

- the executor starts from a clean or explicitly coordinated working tree;
- `RULES.md`, `ARCHITECTURE_CONSTITUTION.md`, `ADR 001`, `SPEC.md`, `CORE.md`,
  `CONFORMANCE.md`, `MEMORY.md`, and this plan have been read;
- the executor records progress in
  [docs/reports/001_zig_vertical_slice_progress.md](../reports/001_zig_vertical_slice_progress.md);
- Stage 1 records the local Zig and parser dependency state before later stages
  rely on it.

Known execution stop conditions:

- Stop if Zig is unavailable and cannot be installed under the user's approval.
- Stop if local tree-sitter grammar sources cannot be pinned or generated
  without changing the parser strategy.
- Stop if a planned implementation choice would require changing the ratified
  constitution.
- Stop if the first slice needs a public contract, persistence, or service to
  pass its tests; that means the plan has grown beyond scope.

## Completion Definition

The plan is complete when the first Zig vertical slice is implemented, verified,
documented, and committed with a clean working tree, and when the progress log
records exact stage outcomes, verification evidence, skipped checks, residual
risk, and next-step handoff.
