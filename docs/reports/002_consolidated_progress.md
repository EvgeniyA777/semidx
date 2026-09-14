---
title: "Consolidated progress report 002"
doc_type: "progress_log"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-14"
---

# 002: Consolidated Progress Report

This consolidated log owns the post-vertical-slice follow-up and the
repository-scale ingestion workstream. It folds the content that briefly lived
as standalone reports 003, 004, and 005 back into report 002, so the reports
directory keeps one historical progress log for this workstream instead of
separate fragments.

Historical anchors are preserved as section headings below. Links that formerly
pointed at the removed report files now point to the corresponding section in
this file.

## 002: Slice Freshness Follow-up

A review of the first vertical slice
([plan 001](../plans/001_zig_vertical_slice.md),
[log 001](001_zig_vertical_slice_progress.md)) found three defects in what that
slice delivered. This log records the fixes.

### Findings And Disposition

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | High | After a failed reanalysis, the unit's earlier assertions stayed queryable as current graph facts. `Index.applyEdit` replaced the unit's contents, then `reconcile.integrate` returned early on a blocking diagnostic without withdrawing or marking anything, and snapshot queries returned the old facts normally. | Fixed. Freshness is now a first-class axis; see below. |
| 2 | Medium | The source container's evidence was stale after a successful edit. `setSourceUnitBytes` swapped the bytes only, so the `file` entity and the repository-to-file ingestion assertion kept the extent computed when the unit was first registered. | Fixed. Ingestion re-establishes what it claims about a unit whenever the contents change. |
| 3 | Low | `Parser.parse` accepted a previous tree, and an adapter test reused one across changed source without `ts_tree_edit`. Not a runtime bug — the analyzer passed `null` — but the API invited the mistake. | Fixed by removing the parameter. |

All three were accepted. None was deferred.

### Finding 1: Freshness

The defect was not that the old assertions were retained. Withdrawing them would
assert an absence nothing observed, and would destroy the identities a later
successful analysis needs in order to preserve them. The defect was that they
were retained *and presented as current*, with nothing telling a consumer that
the source they describe is gone.

Freshness is therefore modelled as its own axis, separate from resolution:

- `model.Freshness` is `current` or `stale`. A fully resolved fact about source
  that has since changed is still a fact about what its producer read, and it is
  still not current; an unresolved assertion about the contents on disk right
  now is current and still unresolved. Collapsing the two would lose information
  in both directions, and would make "we could not re-read this file"
  indistinguishable from "we read it and resolved nothing" — which
  [CONFORMANCE.md](../../CONFORMANCE.md) requires to stay distinguishable.
- Each source unit records `content_revision` (when its contents were
  established) and `analysis_revision` (when a frontend last analyzed it
  successfully). `UnitAnalysis` derives `pending`, `current`, or `stale` from
  the pair, and a `Snapshot` exposes it per unit.
- A claim observed in a unit is current when it was recorded at or after that
  unit's `content_revision`. One rule, applied to entities through a new
  `Entity.observed_revision` and to assertions through the revision they already
  carried. Nothing is special-cased by producer.
- `Index.applyEdit` now performs the edit in its own revision before analysis
  runs. That is what makes the rule work: ingestion establishes the new contents
  and thereby marks the unit's existing analysis stale, and analysis then either
  makes it current again or leaves it stale.
- Snapshot queries take `freshness`, defaulting to `.current`. A caller who did
  not ask for stale claims is never handed one. Stale claims remain in
  `snapshot.assertions` and `snapshot.entities` and are reachable by asking
  (`.freshness = .stale`, or `null` for either), so this is distinguishability,
  not concealment.
- `reconcile.integrate` calls `Graph.markAnalyzed` only on a successful pass,
  and withdraws the previous attempt's diagnostics on every pass, so diagnostics
  always describe the latest attempt rather than accumulating.

One related change fell out of it. `Graph.addEntity` no longer records an
existence assertion as a side effect; the producer that observed the entity
records it, with its own provenance and resolution. Allocating an entity and
claiming it exists are different acts, and only the second is an assertion.

### Finding 2: Source Container Extent

`setSourceUnitBytes` now refreshes the `file` entity's evidence and re-records
both ingestion claims about the unit — that the container exists, and that the
indexed source tree contains it — against the new extent. The `file` entity
keeps its id: its extent is a projection, and a projection moving is not an
identity change.

This also makes ingestion's claims about a stale unit correctly *current*:
ingestion did read the new contents, even when no frontend could analyze them.

### Finding 3: Previous-Tree API

`Parser.parse` no longer takes a previous tree. tree-sitter can reuse one only
if it has been told through `ts_tree_edit` exactly which byte ranges changed;
handing it an unedited tree makes it conclude the text is unchanged and return
the old parse. Nothing upstream tracks edit ranges, so the parameter could only
ever be misused. The replaced test now asserts the property that reuse would
have broken: two parses of different contents through one parser describe their
own contents.

`contract.PreviousParse` stays as the contract-level marker for an adapter that
does track edits.

### Changed Files

- `src/core/model.zig`, `src/core/graph.zig`, `src/core/reconcile.zig`
- `src/frontend/tree_sitter.zig`, `src/frontends/root.zig`
- `src/root.zig`, `src/main.zig`
- `tests/vertical_slice_test.zig`
- `fixtures/vertical-slice/java/edits/05_unparsable.java`
- `fixtures/vertical-slice/clojure/edits/05_unparsable.clj`
- `GLOSSARY.md`, `MEMORY.md`, `CONFORMANCE.md`
- `docs/reports/002_consolidated_progress.md`

### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 37/37 passed, up from 32. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 37/37 passed; the core still builds and is tested with no parser input. |
| `zig build test --summary all` | 66/66 passed, up from 58: core 37, adapter 6, frontends 6, fixture and edit-history 17. |
| `zig build run -- fixtures/vertical-slice/java/Greeter.java fixtures/vertical-slice/clojure/greeter.clj` | Both units reported `current`, 0 stale assertions. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

New tests, each of which fails against the previous implementation:

- **core** — an edit whose analysis fails stops answering current-state queries:
  the unit reports `stale`, the definitions and relationships disappear from
  default queries, they are still reachable as stale, the entities still exist
  so identity survives, and ingestion's claims about the unit are current.
- **core** — a stale unit becomes current again with identity preserved across
  the gap: after a failed analysis and a repair, all entities are `preserved`,
  none created or lost, and the failed attempt's diagnostic is gone.
- **core** — failed analysis of unchanged contents leaves the unit current. This
  is the boundary case: a failure is only a staleness event when the contents
  actually moved.
- **core** — one unit going stale does not make another unit stale.
- **core** — a unit is pending until analyzed and current afterwards.
- **core** — the source container's extent follows an edit, for both the `file`
  entity and the ingestion containment assertion.
- **fixture** — editing the Java fixture into unparsable source stops its facts
  being current, leaves the Clojure unit untouched, and restores the same entity
  ids when the source is repaired.
- **fixture** — the same for the Clojure fixture, checking that the stale
  definition is still reachable by id.
- **fixture** — the source container's extent tracks the file it stands for.
- **adapter** — one parser parses successive contents independently.

### Residual Risk

- **Freshness is per unit, not per claim's dependencies.** A cross-unit
  assertion would be current while the unit it points into is stale. The slice
  has no cross-unit assertions, so nothing exercises this; repository-scale
  ingestion must decide how an edit invalidates claims in *other* units before
  it adds any.
- **Stale claims accumulate.** Nothing ever withdraws them, so a unit that stays
  unparsable keeps its old assertions in memory indefinitely. Bounded here by
  the slice being in-memory and small; a long-lived process needs a policy.
- **Default-current is a query default, not an enforced boundary.** A consumer
  walking `snapshot.assertions` or `snapshot.entities` directly sees everything
  and must consult `assertionFreshness` or `entityFreshness` itself. The arrays
  are documented as raw, but the type does not prevent the mistake.
- Everything in log 001's Residual Risk section still stands.

### Next Handoff

Unchanged from log 001, with one ordering note: the freshness semantics settled
here are a precondition for repository-scale ingestion, because that is where
cross-unit invalidation first becomes possible. `CORE.md` candidate admission is
still independent of both.

## 003: Core Admission Review

This review assesses the `CORE.md` candidates after the first Zig vertical slice
and the freshness follow-up. It records admission of core meaning only. It does
not publish a semantic contract version, declare supported languages, create a
capability matrix, or claim repository-scale coverage.

### Scope

Inputs:

- `ARCHITECTURE_CONSTITUTION.md`, especially sections 1, 3, 4, 5, 6, and 7.
- `SPEC.md`, especially the core contract lifecycle and the five admission
  criteria.
- `CORE.md` candidate definitions before this review.
- `docs/reports/001_zig_vertical_slice_progress.md` and
  `docs/reports/002_consolidated_progress.md`.
- The implementation and tests under `src/`, `tests/`, and
  `fixtures/vertical-slice/`.

Semantic Code Indexing was required by repository policy, but no semidx MCP
tools were available through tool discovery in this environment. The review used
targeted direct inspection instead. The runtime code under review is Zig, which
is not one of the supported languages listed by the current semidx skill.

### Result

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

### Findings

#### Blocker: `DEFINES` Meaning Is Broader In Code Than In The Candidate Text

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

#### Accepted: Structural Entity Kinds

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

#### Accepted: `REFERENCES` And `CALLS`

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

### Evidence

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
- [section 002](#002-slice-freshness-follow-up) records the freshness fix that
  keeps old assertions distinguishable without presenting them as current.

### Verification

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

### Residual Risk

- The accepted roster is not published as a versioned semantic contract.
- There is no capability matrix and no public consumer surface.
- `DEFINES` is deliberately not admitted until its direct-containment meaning is
  settled.
- Cross-unit assertions and invalidation are still absent, so this review does
  not admit `module`, `IMPORTS`, or repository-scale dependency semantics.
- The review accepts meaning for the fixture-scoped frontends only; Java and
  Clojure are not declared supported languages.

## 004: Defines And Contains Split

This section records the follow-up to the `DEFINES` blocker found in
[section 003](#003-core-admission-review). The implementation now separates
direct containment from definition introduction:

- `CONTAINS` records that one source or program container directly contains an
  entity.
- `DEFINES` records that a container directly introduces a program definition.

This remains an unversioned implementation guidance result. It does not publish
a semantic contract version, declare supported languages, or add a public API.

### Context

The first admission review found that `CORE.md` described `DEFINES` as
container-to-definition, while the implementation also used it for
`repository -> file` source-tree containment. External graph-modeling practice
supports keeping those meanings separate: definition/binding claims are narrower
than containment/parenthood claims, and source-file membership should not be
mistaken for a program definition.

Semantic Code Indexing was required by repository policy, but no semidx MCP
tools were available through tool discovery in this environment. The change used
targeted direct inspection instead. Runtime code here is Zig, which is not one
of the supported languages listed by the current semidx skill.

### Decision

`CONTAINS` is admitted as the shared-core relation for direct containment.
Source ingestion uses it for `repository -> file` claims.

`DEFINES` is admitted as the shared-core relation for direct definition
introduction. Its target must be a `definition`. A `repository -> file` relation
is therefore invalid as `DEFINES`.

`CALLS` and `REFERENCES` behavior is unchanged: calls continue to satisfy a
reference query, while both `CONTAINS` and `DEFINES` do not.

### Implementation

- `src/core/model.zig` adds `RelationshipKind.contains`.
- `src/core/graph.zig` records source-unit membership as `CONTAINS` and rejects
  `DEFINES` when the target is not a `definition`.
- `src/core/reconcile.zig` updates stale-source-unit expectations to look for
  current ingestion `CONTAINS` assertions.
- `tests/vertical_slice_test.zig` proves fixture ingestion uses `CONTAINS`
  while frontend definition introduction remains `DEFINES`.
- `CORE.md` accepts `CONTAINS` and `DEFINES` with distinct meanings.
- `MEMORY.md` records the current reality and removes the `DEFINES` blocker from
  near-term priorities.

### Risk Matrix

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Source-tree membership uses containment | `repository -> file` keeps masquerading as a definition introduction | Core unit test and fixture test | Snapshot queries observe `CONTAINS` for source-unit membership | Querying repository `DEFINES` returns nothing | `zig build test-core`, `zig build test` |
| Definition introduction remains narrow | A non-definition target can be recorded as `DEFINES` | Core unit test | `Graph.addRelationship` rejects a live `file` target for `DEFINES` | `repository DEFINES file` fails | `zig build test-core` |
| Reference query semantics stay unchanged | `CONTAINS` or `DEFINES` pollutes "all references" queries | Model unit test | `RelationshipKind.satisfiesReferenceQuery` excludes both | Calls still satisfy the query | `zig build test-core` |
| Frontends stay language-specific | Java/Clojure fixtures lose definition-introduction edges | Fixture integration test | Existing fixture expectations still require file/class/namespace `DEFINES` edges | Source ingestion edge changed independently | `zig build test` |

### Verification

Run after implementation:

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 38/38 tests passed. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 38/38 tests passed; the shared core remains independent of parser inputs. |
| `zig build test --summary all` | 67/67 tests passed across the core, adapter, frontend, and fixture lanes. |
| `zig build run -- fixtures/vertical-slice/java/Greeter.java fixtures/vertical-slice/clojure/greeter.clj` | Printed 1 repository, 2 files, 8 definitions, 31 assertions, 26 facts, 5 unresolved assertions, 0 approximate assertions, and 0 stale assertions. |

### Residual Risk

- `CONTAINS` currently has only source-ingestion fixture evidence for
  `repository -> file`; broader program-container uses remain future endpoint
  expansion work.
- `DEFINES` is admitted for direct introduction in the fixture-scoped frontends,
  not as complete Java or Clojure language support.
- There is still no published semantic contract, capability matrix, or public
  consumer surface.
- `module`, `IMPORTS`, textual inclusion, and cross-unit invalidation remain
  unsettled.

## 005: Repository-Scale Ingestion Progress

Companion log for
[docs/plans/002_repository_scale_ingestion.md](../plans/002_repository_scale_ingestion.md).

### Current Status

Stages 1 through 6 are implemented, verified, and closed. Stage 5 took its
rejected branch: [ADR 003](../adr/003_reject_name_match_assertions.md) refused
repository-wide name matching, so no cross-unit resolution was added, and the
stage delivered the dependency mechanism alone. Stage 6 synchronized the
requirements, conformance, glossary, memory, and this log.

### Stage Log

| Stage | Status | Outcome |
| --- | --- | --- |
| Plan creation | Completed | Created the staged plan and this log. Gate applied; findings below. |
| Stage 1: Source discovery | Completed | `src/source/{root,languages,scan,discovery}.zig`, the `semidx_source` module, `Index.addScan`, and a developer command that takes a root. |
| Stage 2: Unit identity independent of path | Completed | `model.Scope`, unit tombstones, `setSourceUnitPath`, `removeSourceUnit`, and both frontends scoping entities to the unit. |
| Stage 3: Scan reconciliation | Completed | `src/source/registry.zig` decides correspondence as a pure function; `Index.applyScan` applies it; `Analyzer.invocations` measures what was re-read. |
| Stage 4: Affected-region proof at scale | Completed | Per-unit buckets and indexes in the graph, `Graph.unit_work`, `fixtures/repository-scale/`, and scale tests that fail if a keyed lookup regresses into a sweep. |
| Stage 5: Cross-unit dependency tracking | Completed (rejected branch) | [ADR 003](../adr/003_reject_name_match_assertions.md) rejected name-match assertions; `src/core/dependencies.zig` and its wiring were built and proved synthetically. |
| Stage 6: Closure and documentation | Completed | Synchronized `MEMORY.md`, `SPEC.md`, `CONFORMANCE.md`, `GLOSSARY.md`, this log, and the plan lifecycle; recorded review disposition and remaining risks. |

### Plan Readiness Gate

Applied against
[documentation.md](../agent-policy/documentation.md#plan-readiness-gate) before
any implementation.

#### Hard Fail Conditions

| Condition | Result |
| --- | --- |
| Product or runtime behavior unclear, or conflicting with sources of truth | Pass. The plan was written after reports 003 and 004, so it uses the accepted roster including the `CONTAINS`/`DEFINES` split, and changes no accepted meaning. |
| Scope boundaries missing, vague, or allowing unrelated refactoring | Pass. Non-Scope names persistence, public surfaces, ignore-file parsing, language import semantics, snapshot redesign, and performance work explicitly. |
| A key technical decision implicit, unjustified, or externally gated without a stop rule | Pass after correction; see finding 1. |
| Branches mentioned but not carried through stages, files, verification, and DoD | Pass after correction; see finding 1. |
| Stages depending on later stages, or lacking concrete outputs | Pass. Each stage names files or artifacts. Stage 5 depends on Stage 3, not on Stage 4, and the gate records that ordering. |
| DoD not verifiable through files, commands, tests, or artifacts | Pass. Every DoD item is a test, a command, or a document state. |
| Test strategy missing main risks | Pass. The risk matrix covers discovery correctness, core/environment separation, rename identity, identity-loss visibility, affected-region measurement, quadratic behavior, invalidation, approximate-versus-fact, freshness at scale, privacy, and documentation truthfulness. |
| Runtime constraints ignored | Pass. Budgets, symlink handling, temporary-tree isolation, and the no-network constraint are named. |
| Documentation targets contradicting each other or carrying stale bookkeeping | Pass after correction; see finding 2. |
| Requires guessing what to implement, skip, test, or when to stop | Pass. Four stop conditions are stated with resume behavior. |

#### Findings Raised And Fixed Before Execution

1. **Stage 5 was an unresolved branch.** The first draft left "record cross-unit
   name matches as approximate assertions" as a good idea without saying what
   happens if it turns out to conflict with
   [§1](../../ARCHITECTURE_CONSTITUTION.md#1-semantic-graph-is-the-product).
   That is two hard-fail conditions at once: an externally gated decision with no
   stop rule, and a branch not carried through DoD. Fixed by opening the stage
   with an ADR and giving both outcomes a complete DoD, so the plan completes
   either way.

2. **The plan had to be rewritten against a roster that changed while it was
   being written.** Reports 003 and 004 admitted `repository`, `file`,
   `definition`, `CONTAINS`, `DEFINES`, `REFERENCES`, and `CALLS`, and split
   containment from definition introduction. An earlier draft still described
   `repository DEFINES file`. Corrected throughout.

#### Ready Criteria

| Criterion | Result |
| --- | --- |
| Contract changes explicit and tied to sources of truth | Pass. The one model change — identity scope becoming unit identity rather than a path — is stated as a plan-level decision and tied to §4. |
| Scope and non-scope explicit | Pass. |
| Key decisions and rationale recorded | Pass. Seven plan-level decisions, each with its reason. |
| Blockers and branches have precise stop and resume behavior | Pass. |
| Each stage has purpose, ordered dependencies, and concrete outputs | Pass. |
| Verification commands and acceptance checks named | Pass. The lanes are the ones [testing.md](../agent-policy/testing.md#verification-lanes) already records. |
| DoD observable and falsifiable | Pass. The load-bearing one is a frontend invocation count, which fails if a rescan does more work than it should. |
| Risk-based tests mapped to behavior | Pass. |
| Runtime and environment traps considered | Pass. |
| Internally consistent, not overloaded with irrelevant detail | Pass. |

**Gate result: ready for execution.**

### Stage 1 Record

#### What Was Built

- `src/source/languages.zig` owns the one extension-to-language table.
  `semidx.languageForPath` now forwards to it instead of carrying a second copy.
- `src/source/scan.zig` owns the scan value: `ScannedUnit`, `ScanDiagnostic`,
  `Budgets`, `Options`, and the exclusion list. Content identity is SHA-256.
- `src/source/discovery.zig` owns the walk. `scan` opens a root path; `scanDir`
  walks an already-open handle, which is what lets tests work against a
  temporary directory without assuming anything about the working directory.
- `build.zig` gains the `semidx_source` module. It has no C dependency, so it
  joins the `test-core` step; that step's description now reads "every lane that
  needs no parser" rather than naming only the core.
- `Index.addScan` registers a scan's units and records what the scan declined as
  graph diagnostics, so a file that was found but not ingested stays visible.
- `semidx-dev` takes directories as well as files.

#### Decisions Taken During Stage 1

- **Symbolic links are not followed at all.** The plan asked to refuse links
  that leave the root and to terminate on loops; declining every link satisfies
  both with no path arithmetic and no cycle bookkeeping. Every link is reported,
  so a skipped one is never silent. A link pointing inside the root is therefore
  also skipped: a real limitation, recorded below rather than hidden.
- **Exclusion is an explicit directory-name list, not a dot-prefix rule.**
  `.git` must be skipped and `.github` must not be; only a list can express that.
- **Units are sorted by path.** Directory iteration order is a filesystem detail,
  and letting it through would make unit identity allocation in Stage 2 and every
  test over a scan depend on it.
- **Content identity is SHA-256, not a fast 64-bit hash.** This value will decide
  "unchanged, do not reanalyze" and "same unit under a new path". A collision
  there is not a slow answer; it is a wrong graph with a heuristic wearing the
  face of a fact.
- **Policy exclusions produce no diagnostic; everything else does.** A file no
  frontend covers and a directory on the exclusion list are not degradation. A
  budget refusal, an unreadable file, and a symbolic link are.

#### Plan Correction

The plan's Dependency Direction said `source/discovery` depends on "nothing in
`core/`", while Stage 1's task list required one extension-to-language table
shared with `languageForPath`, which returns `model.Language`. Both could not
hold: honoring the first would have forced a second `Language` enum whose first
symptom would be a file that is a source unit to one caller and invisible to
another. The line now permits `core/model` value vocabulary only — `Language`
and `DiagnosticKind` — and forbids `core/graph`, `core/contract`, and
`core/reconcile`. The property being protected, that nothing in the core depends
on the filesystem, is unchanged and is still proved by
`zig build test-core -Dgrammars-dir=/nonexistent`.

#### Defect Found And Fixed During Stage 1

`SourceScan` carries its arena by value, and the returned struct literal
initialized `.arena` before a field that allocated into that arena. The field
initializers run in written order, so the arena state was copied before the last
allocation was made, and that allocation was unreachable from the result. The
leak checker caught it on the empty-tree case, where it was the only allocation.
Fixed by hoisting every allocation above the literal, with a comment saying why
the order matters.

#### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 50/50 passed: core 38, source 12. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 50/50 passed; source ingestion has no parser dependency either. |
| `zig build test --summary all` | 80/80 passed across five lanes, after deleting `.zig-cache/` and `zig-out/`. |
| `zig build run -- fixtures` | Walked the fixture tree, registered 12 units, and reported the two deliberately unparsable fixtures as `pending` rather than as empty files. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

Stage 1 DoD, item by item:

- Tests build a temporary tree and assert the discovered set, including that an
  excluded directory contributes nothing and an unmapped extension is not a
  unit. Two exclusion cases are covered (`.git`, `zig-out`), plus a `.java.bak`
  file that must not match on a suffix.
- A file at the size budget produces a diagnostic naming the limit, and the
  smaller file beside it is still ingested.
- A symbolic link loop terminates: a link to its own containing directory is
  reported, the walk completes, and only the real files are found.
- The unit budget and the depth budget each produce one diagnostic naming the
  limit.
- An unreadable root is `error.RootUnavailable`, not an empty scan.
- A scan of the same tree twice is identical.
- `zig build test-core` passes with no filesystem dependency in `src/core/`.

#### Residual Risk From Stage 1

- A symbolic link pointing inside the root is skipped along with one pointing
  out. Correct for confinement, wrong for a repository that uses links
  internally. The diagnostic makes it visible; widening it needs real path
  resolution and a cycle set.
- `SourceScan` holds its arena by value, so copying one and releasing both is a
  double free. Same shape as `Graph`; documented, not type-enforced.
- `Index.addScan` is first-pass only. Calling it twice rejects the repeated
  paths, because reconciliation against an existing registry is Stage 3.
- Budgets are defaults picked by judgement, not measurement: 4 MiB per file,
  20,000 units, 64 levels. Stage 4 is the first point where a real tree can say
  whether they are reasonable.

### Stage 2 Record

#### The Stop Condition Did Not Fire

The plan's third stop condition was that unit identity might not be makeable
path-independent without changing the accepted `file` definition in `CORE.md`.
It did not apply: that definition already says "Location is a property, not an
identity derived from byte or line position. Renames and moves obey the
constitutional identity and provenance rules", which supports the change rather
than blocking it. No accepted core meaning changed.

#### What Was Built

- `model.Scope` is a union of `repository` and `unit: SourceUnitId`.
  `IdentityEvidence.scope` now carries it instead of a path string.
- Source units carry `removed_revision` and tombstone rather than disappear, so
  a removed unit's identity is never handed to a later one. `SourceUnitView`
  carries the unit's source-container entity, which is how a consumer gets from
  a path to entities now.
- `Graph.setSourceUnitPath` moves a unit: it updates the path property, refreshes
  the container's evidence, and re-records what ingestion claims. It does not
  touch `content_revision`, so a rename does not make a unit stale and owes no
  reanalysis.
- `Graph.removeSourceUnit` withdraws the unit's assertions and removes its
  entities, recording a `removed` identity event for each — a definition that
  left with its file is observable as having left, not merely missing.
- `Snapshot.EntityFilter` gained `path`, resolved through the unit registry.
  `findDefinition(path, name)` keeps its shape, so most call sites did not move.
- Both frontends scope entities to `input.unit.id`.

#### Decisions Taken During Stage 2

- **The source container entity has no name.** Its identity is its unit and its
  role. Naming it by its path would have made the container itself break
  identity on exactly the operation this stage exists to survive. The path lives
  on the unit and in the entity's evidence, both of which a rename refreshes.
- **A missing scope became unrepresentable rather than validated.**
  `ValidationError.MissingIdentityScope` is gone, because `Scope` is a union with
  no empty case. A constraint the type enforces is better than one a function
  checks.
- **A rename is not an edit.** It opens a revision, because it mutates the graph,
  but leaves `content_revision` alone. Freshness therefore stays `current`
  through a rename, which is correct: the contents nobody touched are still the
  contents that were analyzed.
- **Unit identity stays an index into an append-only table**, the same shape
  `EntityId` already uses. Allocated by the graph, never derived from the path,
  never reused because the table only grows.

#### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 56/56 passed, up from 50. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 56/56 passed. |
| `zig build test --summary all` | 87/87 passed, after deleting `.zig-cache/` and `zig-out/`. |
| `zig build run -- fixtures/vertical-slice/java` | Unit paths now come from the registry rather than from identity evidence; output unchanged in shape. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

Stage 2 DoD, item by item:

- A unit-level test renames a unit and asserts that every definition in it, the
  source container itself, and the relationship count between them are unchanged
  — and that what ingestion claims about the unit now carries the new path.
- A test registers two units at the same relative path under different roots and
  asserts they are distinct units whose definitions, identical in every field a
  consumer can name, do not correspond and do not occupy the same slot.
- The existing 81 tests passed unchanged in meaning. The only test edits were
  three filters where `.scope = <path>` became `.path = <path>`, which is the
  same question asked of the registry instead of of identity evidence.
- An end-to-end test renames a real fixture unit, asserts no identity event was
  recorded at that revision, and then edits the renamed unit and gets four
  preserved entities — so identity survives a rename *and* an edit after it.

#### Residual Risk From Stage 2

- Unit identity is an index into an append-only table. Tombstones make removal
  safe, but the table never shrinks, so a long-lived process over a churning
  repository grows it without bound. Same shape as entity tombstones; a
  compaction story belongs with persistence.
- `setSourceUnitPath` rejects a move onto an occupied path. A scan that swaps two
  files' paths therefore cannot be applied as two renames in either order. Stage
  3 owns rescan reconciliation and must handle the swap, probably by resolving
  removals before renames.
- Nothing yet detects a rename. Stage 2 makes one survivable; deciding that a
  removed path and an added path are the same unit is Stage 3's correspondence
  rule, using the content identity Stage 1 already produces.

### Stage 3 Record

#### What Was Built

- `src/source/registry.zig` decides what happened between two scans, as a pure
  function over unit identity evidence. No filesystem, no graph, no frontend —
  which is what lets a swap, an ambiguous move, and a cross-language content
  collision be tested directly instead of through a whole indexing run.
- `model.ContentId`, `model.contentId`, and `model.UnitIdentityEvidence` moved
  into the shared model, so the registry deciding correspondence and the graph
  storing what it already holds agree on content identity exactly rather than
  approximately.
- `Graph.setSourceUnitPath` now records the move as a `preserved` identity event
  and an `identity_correspondence` assertion resolved as a fact. Identical bytes
  under a new path is exact resolution of "the same unit", not a similarity
  score, so it is recorded as established rather than heuristic.
- `Index.applyScan` replaces `addScan`. The first scan against an empty index is
  all additions; every later one is reconciled.
- `Analyzer.invocations` counts how many times a frontend was asked to read a
  unit. This is the stage's load-bearing number.
- `Snapshot.lastIdentityEvent` answers "what most recently happened to this
  entity's identity" without the caller having to know which revision of a
  multi-step operation recorded it.

#### The Correspondence Rule

In order:

1. A path present in both scans is the same unit. Path is unambiguous — a scan
   holds each path once — and it is the strongest evidence available. Whether
   the contents changed decides only whether reanalysis is owed.
2. A unit whose path disappeared corresponds to a new unit with identical content
   and the same language, and only when exactly one of each exists for that
   content.
3. Everything else is a removal or an addition.

Two consequences worth stating, because both were open questions going in:

- **The path-swap problem predicted after Stage 2 does not exist.** If two files
  exchange contents, both paths are present in both scans, so path correspondence
  places both units where they already are and both are reanalyzed. No rename is
  claimed, so no rename has to be applied through a path another unit still
  occupies. Removals are still applied before renames, because a unit can be
  renamed onto a path a *departing* unit held.
- **A file that moved and changed is a removal and an addition.** Nothing
  establishes that the new unit is the old one, and inferring it from similarity
  is exactly what the constitution's identity clause forbids presenting as
  established.

#### Plan Correction

The Stage 3 DoD asked for `lost` for a unit that was renamed while being edited.
That is wrong, and the plan now says so. `lost` means a replacement was
identified but correspondence to it could not be established. For units no such
case exists: a path present in both scans always corresponds, and a path that
disappeared leaves no slot for anything to take. Recording `lost` would name a
replacement the graph did not identify — the precise dishonesty the event exists
to prevent. The DoD now asks for `removed` plus `added`, with a `removed`
identity event for every definition that left, which is what the implementation
does and what the test asserts.

#### Decisions Taken During Stage 3

- **An ambiguous move is reported, not resolved by picking one.** One removed
  unit whose content matches two added units produces no rename, and a diagnostic
  saying why. Choosing arbitrarily would produce a stable-looking identity that
  is stable by luck.
- **A rename requires the same language.** Identical bytes read as two different
  languages are two different units, whatever the byte comparison says.
- **A move owes no reanalysis.** Nothing inside the file changed, so nothing is
  re-read, and the unit does not go stale.
- **Scan-level diagnostics are replaced, not accumulated.** `dropScanDiagnostics`
  withdraws the previous scan's account of the tree before recording this one's,
  the same way per-unit diagnostics already describe only the latest attempt.
- **Lookups are keyed, not scanned.** The registry builds a path map and a
  content map rather than nesting loops, and orphaned units carry their evidence
  with them rather than being looked back up by id. Stage 4 will guard this; it
  was cheaper to not introduce the problem.

#### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 67/67 passed, up from 56: core 44, source 23. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 67/67 passed. |
| `zig build test --summary all` | 106/106 passed, after deleting `.zig-cache/` and `zig-out/`. |
| `zig build run -- fixtures/vertical-slice` | Walked and reconciled the fixture tree; the two unparsable fixtures still report `pending`. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

Stage 3 DoD, item by item:

- Rescanning an unchanged tree invokes no frontend, opens no revision, and
  records no identity event. The test compares the invocation counter and the
  event count across two publishes.
- Moving a file with identical content preserves the unit id, its container
  entity, every definition id inside it, and their relationship counts, records
  `preserved`, and re-reads nothing.
- Moving a file while editing it records `removed` for the old unit with a
  `removed` event for each definition, and `added` for the new one, whose
  definitions are different entities. See the plan correction above.
- Deleting a file removes its entities with recorded events, leaves the other
  unit's entity ids and analysis state untouched, and re-reads nothing.
- The invocation count is asserted directly: a tree of thirteen units with one
  edited file moves the counter by exactly one.

Beyond the DoD, the pure registry has twelve tests of its own covering the first
scan, an unchanged tree, a content change, a move, a move-and-edit, a path swap,
an ambiguous move, a cross-language content collision, unrelated churn beside a
move, and an emptied tree.

#### Residual Risk From Stage 3

- **`applyScan` publishes nothing between its phases, but it does open several
  revisions.** A scan with removals, renames, and edits walks the graph through
  intermediate revisions. No consumer can observe them, because observation is
  `publish`, but a future concurrent reader would need the whole scan to be one
  revision.
- **Reanalysis is decided by content identity alone.** A unit whose own bytes did
  not change is never re-read, which is correct today only because no assertion
  depends on another unit. The moment cross-unit resolution exists, this becomes
  the thing invalidation has to override, which is Stage 5.
- **The unit table still never compacts**, and a churning tree now grows it on
  every rescan rather than only on explicit removal.
- **Nothing measures cost yet.** The thirteen-unit test proves the shape of the
  work; Stage 4 is where a tree large enough to expose an accidental quadratic
  gets built.

### Stage 4 Record

#### The Guard Required Fixing What It Measures

Writing the guard first showed that ingestion was quadratic in three places, all
of them per-unit operations implemented as graph-wide sweeps:

- `dropAssertionsForUnit` and `dropIngestionAssertionsForUnit` filtered every
  assertion in the repository to find one unit's.
- `definitionsInUnit` walked every entity in the repository.
- `unitByPath` walked every unit, and it is called on every registration and
  every move.

Each is O(graph) per unit, so a full scan of n units was O(n²). None of it was
visible at two units, which is exactly why the stage exists.

The fix is to store things the way they are accessed. Assertions and diagnostics
are bucketed by the source unit they were observed in, definitions are indexed
per unit, and paths are indexed to units. Withdrawing one unit's analysis now
touches that unit's bucket and nothing else. `publish` still walks everything —
deliberately, because a consumer observes one complete state — and now
concatenates the buckets, which makes assertion order grouped by unit rather than
global insertion order. That order is still deterministic.

One query was quadratic too, outside the ingestion path: `EntityFilter.path`
resolved a path to a unit once per candidate entity. It resolves once per query
now.

#### How The Guard Works

`Graph.unit_work` counts stored records examined while applying a change scoped
to one source unit. The scale tests build two trees of different sizes, apply the
same one-unit edit to each, and assert the counter moved by exactly the same
amount. If any per-unit operation goes back to sweeping, that number grows with
the tree and the assertion fails.

It was verified by regression rather than by assumption: reverting `filterBucket`
to a graph-wide sweep made the counter read 1532 instead of 524 on the larger
tree, and all three scale tests failed. The change was then reverted.

A second test states the same property from the other side — building a tree of
three times the units costs between two and four times the work, not nine — and
bounds the work per unit by a constant.

#### Measured Publish Cost

`publish` copies the observable state on every call. On a generated tree of 73
units:

| Records | Count |
| --- | --- |
| Source units | 73 |
| Entities | 292 (73 files, 218 definitions, 1 repository) |
| Assertions | 764 |

So one publish copies roughly 1,100 records for 73 units, around 15 per unit,
and it is linear in the graph rather than in the change. **This is recorded as an
accepted cost, not a solved problem.** It is the right shape for a slice that
publishes once per batch of edits and the wrong shape for a consumer that
publishes per query. Changing it means changing what a snapshot is, which is the
storage-and-snapshots item owned by `SPEC.md`, and this plan deliberately does
not touch it.

#### `fixtures/repository-scale/`

Six units, three per language, with a namespace structure and cross-unit
references that are all currently unresolved — `Greeter` names the type `Helper`,
`demo.greeter/greet` names `decorate`, and both are declared in other units. A
test asserts they stay designators with recorded explanations while same-unit
references resolve as facts.

This is the tree Stage 5 needs, and it is small on purpose. The large trees that
make quadratic behavior observable are generated inside the tests: a few dozen
committed files differing only by an index would add noise without adding
evidence. The plan asked for rescan histories in the fixture directory; they are
generated too, for the same reason, and the fixture `README.md` says so.

#### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 67/67 passed. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 67/67 passed. |
| `zig build test --summary all` | 110/110 passed, after deleting `.zig-cache/` and `zig-out/`. |
| `zig build run -- fixtures/repository-scale` | 6 units, 14 definitions, 48 assertions, 5 unresolved, 0 stale. |
| Deliberate regression of `filterBucket` to a graph-wide sweep | All three scale tests failed; reverted. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

Stage 4 DoD, item by item:

- Tests over trees of 25 and 73 units assert the edit cost is equal across them
  and that one frontend invocation happened in each.
- The guard fails if a keyed lookup becomes a scan, demonstrated by doing it.
- The measured `publish` cost is recorded above and named as an accepted risk.

#### Residual Risk From Stage 4

- **`publish` is linear in the graph.** Measured above. Acceptable while
  publication is per batch; not acceptable per query.
- **Entity correspondence within a unit is quadratic in that unit's size.** A
  file with a thousand definitions compares a million pairs. It is bounded by
  what changed, not by the repository, so the guard passes — but a generated
  source file would find it. Fixing it means hashing identity evidence.
- **`Snapshot.entityById` is still a scan.** It is a query convenience and not on
  the ingestion path, so the guard does not cover it; a consumer resolving many
  ids would feel it.
- **The unit table, the entity table, and the identity event log never compact.**
  A long-lived process over a churning tree grows all three without bound.
- **`unit_work` counts what it was told to count.** It covers the operations this
  plan introduced; a future sweep added somewhere uncounted would not fail the
  guard. The counter is a tripwire, not a proof.

### Stage 5 Record

#### The ADR Said No

The stage opened with the question it was written to decide: may a designator be
matched against definitions elsewhere in the tree and recorded as an
`approximate` assertion?

[ADR 003](../adr/003_reject_name_match_assertions.md) answers no. The short form:
§1 constrains what *produced* a claim, not how it is labelled, so a relationship
that would not exist without a string comparison is established by a string
comparison whatever resolution it carries. `ARCHITECTURE_RATIONALE.md` states the
intended reading directly — "Approximate retrieval belongs in projections" — and
prescribes the alternative in the same section: an unresolved target stays
unresolved, because dropping it loses information and promoting it makes the
graph false.

This was not the answer the stage was leaning toward when it was planned. The
plan's own wording ("record such matches as `approximate` assertions") reads as
though the accepting branch were the expected one. Reading the rationale before
answering is what changed it, and that is the reason the plan required an ADR
first rather than a design.

The decision also keeps `approximate` meaningful rather than killing it: it is
for producers that genuinely compute approximate results about program meaning,
not for retrieval standing in for analysis nobody performed.
`Snapshot.countApproximateAssertions` stays honestly at zero.

#### What Was Built

`src/core/dependencies.zig` records that a unit's analysis read something about
another unit, and answers which units a change obliges to be re-read.

- `Dependencies.declare`, `clearDependent` (a reanalysis withdraws what the
  previous run depended on), and `forget` (a departing unit leaves no dangling
  record).
- `Dependencies.propagate` computes the transitive closure, excludes units
  already being reanalyzed, terminates on cycles, and reports `exhausted` rather
  than silently truncating when a chain exceeds its round budget.
- `contract.DraftDependency` and `BatchBuilder.addDependency` let a frontend
  batch declare one; `reconcile.integrate` records them.
- `Index.applyScan` seeds propagation from changed and removed units and
  reanalyzes what it reaches, counting it as `ScanOutcome.invalidated`.

#### Why Build It With No Producer

Nothing declares a dependency today, so the mechanism is a no-op in practice.
That is uncomfortable, and the reason it was still built is specific rather than
general: Stage 3 established the rule that a unit whose own content did not
change is never re-read, and that rule is unconditional and lives in the
registry. It is correct while every assertion comes from a single unit and wrong
the moment one does not.

`ARCHITECTURE_RATIONALE.md` argues that incrementality cannot be retrofitted
because doing so means rewriting storage, identity, invalidation, and observation
together. The same argument applies to the override: adding it after a system has
assumed it never needs one is the retrofit. Building it now costs one module and
makes the next plan's cross-unit work an addition rather than a rewrite.

#### A Finding The Contract Handed Back

A frontend is given one source unit and sees nothing else, so it has no way to
name another unit's id — which means no frontend can populate `DraftDependency`
even in principle. Only a synthetic batch can.

That is not a gap in this stage; it is the shape of the next one. When cross-unit
resolution arrives, the frontend contract needs a way for a frontend to be told
what else exists, and that is a contract change rather than a frontend change.
The doc comment on `DraftDependency` says so.

#### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 80/80 passed, up from 67. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 80/80 passed. |
| `zig build test --summary all` | 123/123 passed, after deleting `.zig-cache/` and `zig-out/`. |
| `zig build run -- fixtures/repository-scale` | 6 units, 48 assertions, 5 unresolved, **0 approximate**. |
| `zig fmt --check build.zig src tests` | Clean. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

Stage 5 DoD, on the rejected branch:

- The dependency mechanism is proved either way, and it is: declaring a
  dependency through a frontend batch causes the provider's change to reach the
  dependent, and the dependent's change to reach the provider nothing.
  Reanalysis withdraws the previous run's declarations; a departing unit leaves
  no record pointing at it. Ten further tests cover propagation directly:
  transitivity, cycles, self-declaration, already-reanalyzed exclusion, and
  budget exhaustion.
- The ADR exists, is linked from the ADR index, and its consequences are
  recorded here.
- The progress log records the reasoning, which is this section.

#### Residual Risk From Stage 5

- **A dependency is unit-to-unit, not name-to-name.** Adding a new unit
  therefore invalidates nothing, because no declaration can name a unit that did
  not exist when it was written. A name-grained rule would handle it, and the
  `reason` field is where that refinement goes.
- **Propagation runs once per scan, over the declarations as they stood before
  it.** A reanalysis that declares new dependencies does not have those chased in
  the same pass. Unobservable with no producer; a defined limit to revisit with
  one.
- **The mechanism is unexercised in production paths.** Its tests are synthetic
  by necessity. Speculative infrastructure is a real cost, and the justification
  above is the whole of it.

### Stage 6 Record

#### What Was Closed

- `MEMORY.md` now records the repository-scale ingestion reality after Stages 1
  through 5 instead of saying Stage 5 is still next.
- `SPEC.md` now distinguishes what this plan settled for source identity and
  invalidation from what remains open for publication and language-correct
  cross-unit semantics.
- `CONFORMANCE.md` now records the new evidence this plan supplies without
  claiming an executable gate, a capability matrix, a semantic contract version,
  or admitted `module` / `IMPORTS`.
- `GLOSSARY.md` now owns the new vocabulary introduced by this plan.
- This plan and progress log are marked completed and historical.

#### Engineering Review Disposition

An architecture review raised three concerns after Stage 5. Rechecked against
the constitution, plan, progress log, ADR 003, implementation, and tests:

1. **Move plus edit losing unit identity.** Accepted as a product risk, not as a
   confirmed constitutional defect. The current rule deliberately preserves only
   exact correspondence: same path, or unique identical content under a new path.
   A file that moved and changed is removal plus addition, with visible identity
   events. The practical concern is real for common IDE refactors such as
   renaming a Java class and file together. The next improvement should be a
   stronger evidence rule, such as explicit VCS/IDE move events or
   language-aware refactoring evidence, not similarity presented as a fact.
2. **No cross-unit impact analysis yet.** Accepted as the next capability gap,
   not as evidence that the graph is fake. ADR 003 rejects only text-derived
   name matching as a graph assertion; it explicitly leaves language-correct
   scoping as the right path. The dependency mechanism is ready, but it has no
   production producer until a frontend can resolve across units by language
   rules.
3. **Default `.current` hides stale claims.** Rejected as a core defect. The
   default is intentionally current-only so stale facts about old source do not
   answer questions about the current source. A last-known-good view may be a
   future consumer/query mode, but it should not replace the core default.

One additional confirmed documentation issue was found during that review:
`MEMORY.md` and the Stage 6 row in this log were stale after Stage 5. This
closure fixes that issue.

#### Verification

| Command | Result |
| --- | --- |
| `zig build test-core --summary all` | 80/80 tests passed. |
| `zig build test-core -Dgrammars-dir=/nonexistent --summary all` | 80/80 tests passed; parser-independent lanes still do not need grammar inputs. |
| `zig build test --summary all` | 123/123 tests passed. |
| `zig fmt --check build.zig src tests` | Clean. |
| `zig build run -- fixtures` | Indexed 18 source units; reported 58 definitions, 211 assertions, 182 facts, 29 unresolved assertions, 0 approximate assertions, and 0 stale assertions. |
| `./scripts/check-agent-attribution.sh --all` | Passed. |

### Open Questions After Closure

These are the questions most likely to need follow-up now that repository-scale
ingestion exists:

- Whether exact-content-only rename correspondence is too narrow to be useful in
  practice. The plan chooses it deliberately over a similarity heuristic; if real
  use shows it almost never fires, the answer is a stronger *evidence* rule, not
  a guess presented as a fact.
- Whether unit identity should survive a root change, not only a path change. The
  plan scopes identity to one root; multi-root indexing is not in scope and would
  be a `SPEC.md` source-identity question.
- How a future frontend gets enough repository context to produce
  language-correct cross-unit facts and dependencies.
- What snapshot representation should replace whole-state copying if the process
  becomes long-lived or publishes per query instead of per edit batch.

### Blockers

None for plan creation.

Neither anticipated Stage 1 blocker materialized. `std.Io.Dir.iterate` and
`openDir` with `follow_symlinks = false` were sufficient, and the symlink test
needed no platform scoping beyond skipping itself if the filesystem refuses to
create a link.

Neither anticipated Stage 2 blocker materialized. The `scope` change touched
both frontends and three test filters and nothing else, and the stop condition
did not apply.

The first anticipated Stage 3 blocker dissolved on contact: a path swap is not a
rename under the correspondence rule, so it never needs to be applied as one. The
second stands as a decision rather than a blocker — exact-content moves are
claimed, everything else is a removal and an addition.

Both anticipated Stage 4 blockers were resolved as predicted: large trees are
generated in the tests, and `Graph.unit_work` became the countable proxy for
graph-level work.

Both anticipated Stage 5 blockers materialized, and both were handled as the plan
provided for. The ADR did conclude against the approximate branch, and the
mechanism alone is indeed the thinner result. The unconditional Stage 3 rule was
overridden in `Index.applyScan` rather than in the registry, which still knows
nothing about dependencies.

Stage 6 had no blockers.

### Residual Risk

The remaining risk is no longer whether repository-scale ingestion works at all;
that has evidence. The remaining risks are the limits it deliberately exposes:

- exact-content-only move correspondence is conservative and may miss common
  refactors until stronger external or language evidence exists;
- cross-unit facts still do not exist, so dependency propagation is proven only
  synthetically;
- `module` and `IMPORTS` now have a repository, source-unit identity, and an
  invalidation mechanism to build on, but still lack common meaning and frontend
  evidence;
- snapshot publication still copies the observable graph, which is measured and
  accepted for batch publication but unsuitable as a per-query strategy;
- long-lived operation still needs compaction for source units, entities,
  interned strings, stale assertions, and identity events.

### Next Handoff

Plan 002 is closed. The next architectural plan should not reopen repository
discovery or identity. It should choose one narrow producer of legitimate
cross-unit evidence, likely language-correct Java package scoping or a prior
source-identity evidence plan for explicit move events, and then update
`CORE.md` / `SPEC.md` only if that evidence actually requires admission work.
