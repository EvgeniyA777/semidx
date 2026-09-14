---
title: "Core admission review"
doc_type: "review"
lifecycle: "completed"
status: "final"
agent_action: "historical_reference_only"
updated: "2026-09-14"
---

# 003: Core Admission Review

This review assesses the `CORE.md` candidates after the first Zig vertical slice
and the freshness follow-up. It records admission of core meaning only. It does
not publish a semantic contract version, declare supported languages, create a
capability matrix, or claim repository-scale coverage.

## Scope

Inputs:

- `ARCHITECTURE_CONSTITUTION.md`, especially sections 1, 3, 4, 5, 6, and 7.
- `SPEC.md`, especially the core contract lifecycle and the five admission
  criteria.
- `CORE.md` candidate definitions before this review.
- `docs/reports/001_zig_vertical_slice_progress.md` and
  `docs/reports/002_slice_freshness_followup.md`.
- The implementation and tests under `src/`, `tests/`, and
  `fixtures/vertical-slice/`.

Semantic Code Indexing was required by repository policy, but no semidx MCP
tools were available through tool discovery in this environment. The review used
targeted direct inspection instead. The runtime code under review is Zig, which
is not one of the supported languages listed by the current semidx skill.

## Result

| Kind | Result | Reason |
| --- | --- | --- |
| `repository` | Accepted | Source ingestion establishes one source-tree root with graph provenance and no language-specific meaning. |
| `file` | Accepted | Source units are source containers, not chunks; identity survives content edits while extent remains evidence. |
| `definition` | Accepted | Java classes/methods and Clojure namespaces/vars contribute the same core kind while language meaning stays in extensions. |
| `module` | Still blocked | No common meaning has been chosen across namespaces, packages, compilation units, and future source organization. |
| `DEFINES` | Not admitted | The candidate meaning and implementation evidence are not yet aligned: the code uses it for both source-tree containment and program definition containment. |
| `REFERENCES` | Accepted | Both fixtures produce designation relationships with fact and unresolved resolution states, without making unresolved targets into nodes. |
| `CALLS` | Accepted | Both fixtures produce invocation relationships as a specialization of references, and reference queries count an occurrence once. |
| `IMPORTS` | Still blocked | It depends on `module`, and common availability/import semantics remain unsettled. |

## Findings

### Blocker: `DEFINES` Meaning Is Broader In Code Than In The Candidate Text

`CORE.md` described `DEFINES` as a relationship from a container to a
`definition`. The implementation also records `repository DEFINES file` as the
source-ingestion claim that the indexed source tree contains a source unit.

That source-container relationship may be valid core semantics, but it should
not be admitted accidentally under text that says the target is only a
definition. The project must choose one of two small model directions before
admission:

- keep `DEFINES` as definition-introduction only and introduce a separate source
  containment relationship later; or
- define `DEFINES` as general direct containment/introduction across source
  containers and program entities, with fixtures that prove both uses.

Until that choice is made, `DEFINES` remains a blocked candidate.

### Accepted: Structural Entity Kinds

`repository`, `file`, and `definition` satisfy the admission criteria for the
declared fixture coverage:

- Adequacy: they carry the minimum cross-language questions about what source
  tree is indexed, which source units exist, and which program entities exist.
- Identical meaning: the shared kind does not encode Java classes, Java methods,
  Clojure namespaces, Clojure vars, or Clojure forms. Those meanings stay in
  `ExtensionPayload`.
- Honest absence: unsupported constructs, unavailable analysis, parse failures,
  confirmed absence, unresolved targets, and stale claims stay distinguishable.
- Subsidiarity: these are common graph questions, not language-pair mappings.
- Common cost: both current frontends already declare coverage and report
  unsupported constructs rather than silently widening the core.

The acceptance is intentionally scoped. Generated source, virtual source,
anonymous definitions, stronger source identity across renames, and a published
coverage matrix remain future requirements.

### Accepted: `REFERENCES` And `CALLS`

`REFERENCES` and `CALLS` satisfy the admission criteria for the initial endpoint
set of `definition`:

- Java records type references and method invocations; Clojure records symbol
  designations and head-position invocations.
- Resolved endpoints are entity targets; unresolved endpoints stay designators.
- A call is a specialized reference: the reference query includes calls, and one
  occurrence is counted once.
- Dispatch, receivers, imports, macro expansion, local bindings, overloads, and
  inheritance remain coverage limitations rather than hidden core semantics.

Endpoint expansion beyond `definition` and complete dispatch resolution remain
future admission or coverage work.

## Evidence

Implementation evidence:

- `src/core/model.zig` defines `EntityKind` as `repository`, `file`, and
  `definition`, and `RelationshipKind` as `defines`, `references`, and `calls`.
- `src/core/model.zig` keeps `Resolution` separate from `Freshness`, and rejects
  invalid assertion shapes.
- `src/core/graph.zig` allocates ids, records source-ingestion claims, publishes
  consistent snapshots, and defaults entity/relationship/assertion queries to
  current freshness.
- `src/core/contract.zig` keeps frontends from allocating graph identity and
  requires batches to report capabilities, assertions, and diagnostics.
- `src/frontends/java.zig` keeps Java-specific constructs in `java.*`
  extension labels.
- `src/frontends/clojure.zig` keeps Clojure-specific constructs in `clojure.*`
  extension labels.
- `src/core/reconcile.zig` preserves identity through corresponding observations
  and records identity breaks explicitly.

Fixture and test evidence:

- `tests/vertical_slice_test.zig` checks Java entity and relationship extraction,
  Clojure entity and relationship extraction, cross-language graph coexistence,
  call/reference occurrence counting, unresolved targets, edit-time identity
  preservation, rename identity loss, source-container extent refresh, and stale
  current-query exclusion after failed analysis.
- `fixtures/vertical-slice/java/` and `fixtures/vertical-slice/clojure/` provide
  the declared two-language fixture coverage and edit histories.

Document evidence:

- `docs/reports/001_zig_vertical_slice_progress.md` records the implemented
  slice and its original verification.
- `docs/reports/002_slice_freshness_followup.md` records the freshness fix that
  keeps old assertions distinguishable without presenting them as current.

## Verification

The admission review was documentation-only. Verification was run after updating
`CORE.md`, `MEMORY.md`, and this report:

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 37/37 tests passed. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 37/37 tests passed; the shared core remains independent of parser inputs. |
| `zig build test --summary all` | 66/66 tests passed across the core, adapter, frontend, and fixture lanes. |
| `zig build run -- fixtures/vertical-slice/java/Greeter.java fixtures/vertical-slice/clojure/greeter.clj` | Printed 1 repository, 2 files, 8 definitions, 31 assertions, 26 facts, 5 unresolved assertions, 0 approximate assertions, and 0 stale assertions. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |
| `git diff --check` | Clean. |

## Residual Risk

- The accepted roster is not published as a versioned semantic contract.
- There is no capability matrix and no public consumer surface.
- `DEFINES` is deliberately not admitted until its direct-containment meaning is
  settled.
- Cross-unit assertions and invalidation are still absent, so this review does
  not admit `module`, `IMPORTS`, or repository-scale dependency semantics.
- The review accepts meaning for the fixture-scoped frontends only; Java and
  Clojure are not declared supported languages.
