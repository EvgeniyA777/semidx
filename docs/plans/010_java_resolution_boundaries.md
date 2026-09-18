---
title: "Java resolution boundaries"
doc_type: "plan"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-18"
---

# 010: Java Resolution Boundaries

**Executed.** See
[the progress log](../reports/010_java_resolution_boundaries_progress.md) for the
evidence, the decisions, and one correction to this plan's premise: the false
fact Stage 3 removed occurred zero times on the repository Stage 1 probed.

## Goal

Make semidx answer orientation and impact questions on a Java repository that
is not this one, and remove the false-fact risk that blocks every further Java
widening.

The intended user value is the first case where semidx serves someone other
than its own development: a developer connects it to a Java working copy and
gets bounded, honest answers about their own source — what exists, who calls
what, and where the graph's knowledge stops.

This is the first plan executed under the adoption track in
[the roadmap](../design/001_project_roadmap.md): work is chosen because it moves
semidx toward the audience named in
[the adoption strategy](../design/002_product_adoption_strategy.md), not because
it improves semidx's view of itself.

## Start Rule

Stage 1 is a go/no-go probe and must complete before any behavior changes.

Stop and re-open the language choice if Stage 1 shows that first-party-only
resolution cannot answer the questions the adoption strategy names. Record the
finding in the progress log and in
[Follow-up 003](../followups/003_java_classpath_boundaries.md); do not proceed to
Stage 2 on the assumption that later stages will rescue a thin result.

Proceed if Stage 1 shows useful first-party answers, even where cross-dependency
questions stay unresolved. Unresolved-but-honest is the expected result at the
dependency boundary and is not a stop condition.

Stage 1 finding false facts is not a stop condition either: removing them is
what Stages 2 and 3 exist for.

## Scope

- Measure semidx against an external Java repository and record honest
  resolution outcomes for the questions agents actually ask.
- Decide how classpath or module visibility enters Java resolution evidence.
- Make Java same-package resolution respect that boundary, so independent build
  modules sharing a package name stop resolving into each other.
- Add Java single-type imports if Stage 1 evidence shows they carry weight.
- Update tests, fixtures, the capability matrix, the local preview reference,
  operational memory, and the follow-up register.

## Non-Scope

Do not admit `module` or `IMPORTS` into the shared core. Their admission
questions are owned by [CORE.md](../../CORE.md) and need common meaning across
frontends, which one Java plan cannot supply.

Do not read `.jar` files, class files, or any compiled artifact. semidx ingests
source units; a dependency without source in the working copy stays unresolved.

Do not execute Maven, Gradle, or any build tool, and do not resolve dependencies
over the network. Local operation without network is constitutional.

Do not widen Java same-package facts, add method-level call resolution, add type
hierarchy, or add field and member references in this plan. Those wait on the
boundary this plan establishes.

Do not change MCP tool result shape, budgets, or the text fallback.
[ADR 007](../adr/007_text_fallback_migration_flag.md) owns the fallback
separately and its work must not enter this plan's stages or commits.

Do not change Zig or Clojure frontend behavior.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  sections 3, 6, 7, and 8.
- [CORE.md](../../CORE.md), for the `module` and `IMPORTS` admission status and
  the subsidiarity criterion that governs whether a kind may enter the core.
- [SPEC.md](../../SPEC.md), for core admission criteria and coverage
  requirements.
- [ADR 003](../adr/003_reject_name_match_assertions.md), for why repository-wide
  name matching may not establish graph authority.
- [ADR 004](../adr/004_allow_java_same_package_type_resolution.md), for the
  decision this plan bounds.
- [Follow-up 003](../followups/003_java_classpath_boundaries.md), for the
  accepted deferred finding, its acceptance direction, and its required tests.
- [Plan 003](003_java_package_type_resolution.md) and
  [its progress log](../reports/003_java_package_type_resolution_progress.md),
  for what same-package resolution currently establishes and its residual risk.
- [The adoption strategy](../design/002_product_adoption_strategy.md), for the
  questions a probe must ask and what counts as a useful answer.

## Current Evidence

Java same-package top-level type resolution is implemented and is the project's
first production cross-unit fact. Its known defect is recorded in Follow-up 003:
resolution treats the whole indexed repository as one classpath, so two build
modules containing the same package name can resolve into each other as a
`REFERENCES` fact. That is a false fact under constitution section 3, and it
scales with repository size — exactly the repositories this plan targets.

[CORE.md](../../CORE.md) records `module` as a blocked candidate and `IMPORTS`
as blocked on it. Its first remaining admission question is whether a common
`module` meaning exists at all.

All Java evidence in the project is fixture-scoped. Nothing records whether
semidx can ingest a real Java repository, how long that takes, how much memory
it needs, what share of its assertions resolve, or whether the answers help. No
plan has yet been justified by evidence from a repository semidx does not own.

## Plan-Level Decisions

**Classpath boundaries stay in Java extension vocabulary.** Admitting a
shared-core `module` requires demonstrating a common question across frontends;
[CORE.md](../../CORE.md) explicitly rejects admission that rests on
pair-specific mappings. A single Java plan cannot produce that evidence, and
producing it badly would freeze a wrong core kind. Java carries the boundary in
its own extension vocabulary, the core roster is untouched, and the admission
question stays open for a later plan with multi-language evidence.

**Absence of boundary data leaves references unresolved.** When semidx cannot
establish which sources share a visibility scope, a reference stays unresolved.
It must never fall back to selecting by repository-wide name, which is the
current defect and what [ADR 003](../adr/003_reject_name_match_assertions.md)
forbids.

**Boundaries are derived from source layout, not from build execution.** What
evidence establishes a boundary is Stage 2's decision, but it is read from the
working copy. No build tool runs, no network is used, and an unreadable or
ambiguous layout yields unresolved rather than a guess.

**The dependency edge is honestly unresolved, not missing.** A reference to a
type whose source is not in the working copy is an unresolved assertion carrying
its designator. It must be distinguishable from a confirmed absence and from an
unsupported construct, per constitution section 6.

**The probe can stop the plan.** Stage 1 is real evidence gathering with a real
no-go, not a formality that precedes work already decided on.

## Architecture Boundaries

1. Java frontend
Responsibility: Java definitions, references, package and import evidence,
boundary evidence in Java extension vocabulary, and the resolution rules that
turn them into facts or unresolved assertions.
Does not know about: MCP rendering, response budgets, or other frontends.

2. Shared core
Responsibility: entities, relationships, assertions, resolution categories,
freshness, identity, and snapshots.
Does not know about: Java packages, classpaths, build modules, or directory
layout conventions. This plan adds no core kind.

3. Ingestion
Responsibility: discovering and reconciling source units under the indexed root.
Does not know about: Java visibility scopes. If boundary evidence needs a file
that is not a Java source unit, its intake is Stage 2's explicit decision, not
an implicit widening of what ingestion treats as source.

4. MCP preview
Responsibility: projecting whatever the graph establishes.
Does not know about: this plan. No tool shape changes; new resolution outcomes
must surface through existing resolution, designator, and freshness fields.

5. Tests and fixtures
Responsibility: proving that boundaries are respected, that ambiguity yields
unresolved, and that the Plan 003 fixtures still resolve.

## Stages

### Stage 1: External Java Evidence Probe

Purpose: establish whether semidx is useful on a Java repository it does not
own, before changing any behavior.

Likely files:

- `docs/reports/010_java_resolution_boundaries_progress.md`

Required behavior:

- Choose one external Java repository that is open source, multi-module, and
  large enough that manual orientation is genuinely hard. Record its name,
  commit, module count, and Java source-unit count. Do not commit its source
  into this repository.
- Index it with `zig build mcp -- --root <dir>` and record whether ingestion
  completes, how long it takes, peak memory, and every diagnostic raised.
- Ask a fixed question set drawn from
  [the adoption strategy](../design/002_product_adoption_strategy.md): what
  exists in a chosen area, where a named definition is introduced, who
  references it, what neighborhood matters for a focused edit, and whether the
  answer is current.
- Classify every answer as useful, thin, or misleading. A misleading answer is
  one presenting an unestablished claim as a fact; record each with the exact
  call and result.
- Count same-package resolutions that cross a build-module boundary. This is the
  Follow-up 003 defect measured on real source rather than fixtures.
- Record the share of references that stay unresolved, split into those whose
  target is in the working copy and those whose target is a dependency without
  source. These are different problems and only the first is this plan's.

Done when:

- The progress log records the repository identity, ingestion outcome, the
  question set with classified answers, the cross-module false-fact count, and
  the two unresolved shares.
- The log states go or no-go against the Start Rule, with the evidence for it.

### Stage 2: Boundary Representation Decision

Purpose: decide what establishes a Java visibility boundary, and record it where
a later plan can find it.

Depends on: Stage 1 go.

Likely files:

- `docs/adr/008_java_visibility_boundaries.md`
- `docs/reports/010_java_resolution_boundaries_progress.md`

Required behavior:

- Decide what source-derived evidence establishes that two Java source units
  share a visibility scope. Candidates include source-root layout, directory
  structure relative to declared packages, and declared build-module descriptors
  read as data. The decision names what is read, what is ignored, and why.
- State precisely what happens when the evidence is absent, ambiguous, or
  contradictory. The answer is unresolved in every such case.
- Keep every new term in Java extension vocabulary. If the decision appears to
  need a shared-core kind, stop and record that as a CORE admission question
  instead of admitting one here.
- Answer all eight questions of constitution section 11 explicitly.
- Record what the decision does not enable, so a later plan does not read it as
  permission to widen.

Done when:

- The ADR is written, its constitutional test is complete, and it names the
  fixtures and checks Stage 3 must satisfy.

### Stage 3: Boundary-Aware Same-Package Resolution

Purpose: remove the false fact.

Depends on: Stage 2.

Likely files:

- `src/frontends/` Java frontend sources
- `fixtures/` Java fixtures
- `tests/` Java frontend and core integration tests
- `docs/reports/010_java_resolution_boundaries_progress.md`

Required behavior:

- Apply the Stage 2 boundary so same-package resolution establishes a fact only
  within one visibility scope.
- Leave cross-boundary and ambiguous cases unresolved, carrying their designator
  and producer, distinguishable from confirmed absence and unsupported
  constructs.
- Implement the required tests named in
  [Follow-up 003](../followups/003_java_classpath_boundaries.md): two
  independent roots sharing a package and class name do not become one visible
  package; a declared dependency permits resolution only in the allowed
  direction; ambiguous or unavailable boundary data leaves references
  unresolved; Plan 003 one-package fixtures still resolve.
- Re-run the Stage 1 question set against the same external repository and
  record the change in the cross-module false-fact count. The target is zero.

Done when:

- The false-fact count on the external repository is zero, proven by re-running
  the recorded calls.
- All Follow-up 003 required tests pass and Plan 003 fixtures still resolve.

### Stage 4: Java Single-Type Imports

Purpose: convert the most common remaining unresolved first-party reference into
a fact, if Stage 1 showed it matters.

Depends on: Stage 3.

Conditional: execute only if Stage 1 recorded that single-type imports account
for a material share of unresolved in-working-copy references. If Stage 1 showed
they do not, skip this stage, record the measurement that justified skipping,
and go to Stage 5.

Likely files:

- `src/frontends/` Java frontend sources
- `fixtures/` Java fixtures
- `tests/` Java frontend tests
- `docs/spec/capability_matrix.md`

Required behavior:

- Resolve a single-type import to an indexed Java source unit only when the
  Stage 2 boundary permits it and the match is exact.
- Leave on-demand and wildcard imports unresolved. They name a scope, not a
  type, and resolving them by search would reintroduce the Stage 3 defect in
  another form.
- Leave an import whose target has no source in the working copy unresolved with
  its designator intact.

Done when:

- Single-type imports within a permitted boundary are facts, every other import
  form stays unresolved, and the re-run question set shows the improvement.

### Stage 5: Documentation, Capability Matrix, And Closure

Purpose: make the new boundary legible to a user who has no plan history.

Likely files:

- `docs/spec/capability_matrix.md`
- `docs/mcp/local_preview.md`
- `docs/followups/003_java_classpath_boundaries.md`
- `docs/followups/README.md`
- `docs/design/001_project_roadmap.md`
- `MEMORY.md`
- `docs/reports/010_java_resolution_boundaries_progress.md`

Required behavior:

- State in the capability matrix what Java resolution establishes, within what
  boundary, and what stays unresolved — naming the dependency edge explicitly so
  a user is not surprised by it.
- Record the external-repository evidence as the project's first non-fixture
  coverage statement, and mark clearly that it is one repository.
- Close Follow-up 003 against ADR 008 and this plan, or split any unresolved
  part into a narrower follow-up.
- Update the roadmap's near-term direction: record that the adoption track was
  entered and what the probe showed.
- Record residual risk: dependency-edge references remain unresolved by design;
  framework and dependency-injection relationships are invisible to a
  source-only graph; evidence rests on one external repository.

Done when:

- A reader who has never seen this plan can tell from the capability matrix what
  Java answers are facts and where the graph stops.
- The progress log records verification, review outcome, residual risk, and a
  next-step recommendation.

## Verification Strategy

Run:

- `./scripts/check-zig-version.sh`
- `zig fmt --check build.zig src tests`
- `zig build test-core`
- `zig build test`
- `zig build dogfood`
- `zig build preview-gate --summary all`

Add focused tests for:

- two independent source roots sharing a package and class name staying separate;
- a declared dependency permitting resolution in one direction only;
- absent, ambiguous, and contradictory boundary evidence all yielding unresolved;
- Plan 003 one-package fixtures continuing to resolve unchanged;
- unresolved cross-boundary references keeping designator, producer, and
  freshness, and staying distinguishable from confirmed absence and unsupported
  constructs;
- single-type import resolution and the continued non-resolution of wildcard and
  on-demand imports, if Stage 4 executes.

External-repository evidence is recorded in the progress log, not committed as a
fixture and not turned into a release gate. One repository is evidence, not a
conformance target.

## Definition Of Done

- Java same-package resolution establishes facts only within an explicit
  visibility boundary, and the cross-module false-fact count on the probed
  external repository is zero.
- Absent or ambiguous boundary evidence yields unresolved assertions, never a
  name-selected fact.
- References to dependencies without source in the working copy are unresolved
  with their designators intact, and are distinguishable from confirmed absence
  and unsupported constructs.
- No shared-core kind was admitted; `module` and `IMPORTS` remain open questions
  owned by CORE.md.
- No build tool was executed and no network access was required at index or
  query time.
- The project holds recorded evidence of semidx running against a Java
  repository it does not own, including what it could not answer.
- Follow-up 003 is closed or narrowed, and the capability matrix states the Java
  boundary in terms a user can act on.
