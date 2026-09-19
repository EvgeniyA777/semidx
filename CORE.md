---
title: "Shared-core roster"
doc_type: "specification"
lifecycle: "active"
status: "draft"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# semidx Shared Core

The shared-core kinds and their admission assessments. The first admission
review accepted an initial unversioned roster, recorded in
[report 002 section 003](docs/reports/002_consolidated_progress.md#003-core-admission-review), and the
definition/containment split admitted `CONTAINS` and `DEFINES`, recorded in
[report 002 section 004](docs/reports/002_consolidated_progress.md#004-defines-and-contains-split). That is not a
published semantic contract version, not a runtime support claim, and not an
immutable API. Accepted definitions can be used by the implementation; publishing
them to consumers still requires the lifecycle work in [SPEC.md](SPEC.md).

## Authority And Lifecycle

[ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md#6-language-frontends-preserve-meaning)
owns the constitutional boundary for the shared core and language extensions.
This file owns definitions and admission evidence.
[SPEC.md](SPEC.md#core-contract-lifecycle) owns publication, versioning,
deprecation, and migration procedures.

Candidates can be edited, replaced, or rejected. An open admission blocks the
candidate and all definitions depending on it, transitively. Acceptance requires
a complete assessment against the
[core admission criteria](SPEC.md#core-admission-criteria), resolved
dependencies, and conformance evidence for the declared language/frontend
coverage. A heading or an example in this file does not constitute acceptance.

Adequacy is a floor on the accepted roster: the constitution requires a core
sufficient to ask what entities exist and what refers to what. A candidate
carrying that floor may be replaced by a better definition; rejecting it and
leaving the floor unmet is not an available outcome.

Concrete membership questions belong here. A question requiring a change to
constitutional meaning is handled under the constitution's open-question and
ratification rules; calling it an admission question does not change that
requirement.

## Admission Status

| Kind | Status | Dependencies | Remaining admission work |
| --- | --- | --- | --- |
| `repository` | Accepted | None | Publication version and coverage matrix |
| `file` | Accepted | `repository` | Publication version, origin coverage, and coverage matrix |
| `definition` | Accepted | None | Publication version, anonymous-construct coverage, and coverage matrix |
| `module` | Blocked candidate | None | Common meaning and frontend coverage |
| `CONTAINS` | Accepted | Admitted entity kinds | Publication version, endpoint expansion rules, and coverage matrix |
| `DEFINES` | Accepted | `CONTAINS`, `definition` | Publication version, endpoint expansion rules, and coverage matrix |
| `REFERENCES` | Accepted | `definition` for the initial endpoint set | Publication version, endpoint expansion rules, and coverage matrix |
| `CALLS` | Accepted | `definition`, `REFERENCES` | Publication version, dispatch coverage, and coverage matrix |
| `IMPORTS` | Blocked candidate | `file`, `module` | Module admission and import semantics |

Source containers are entities under the constitution's Defined Terms. Source
ingestion produces their assertions with its actual provenance. Their
architectural status is settled; particular kinds still require admission.

Acceptance here means the core meaning passed the admission criteria for the
declared fixture coverage. It does not mean the project has a published contract,
a supported-language matrix, repository-scale ingestion, persistence, or a public
surface.

## Entity Definitions

### `repository`

The root source container for one indexed source tree. Every entity belongs to
one such indexing scope. This does not assert a particular version-control
system, source layout, or module structure.

**Admission result.** Accepted by
[report 002 section 003](docs/reports/002_consolidated_progress.md#003-core-admission-review). Adequacy: scopes existence/reference queries.
Identical meaning: source-tree membership is independent of language.
Honest absence: ingestion must establish a root for a successful index; failure
is an error, not absence. Subsidiarity: a common query scope cannot depend on an
optional pairwise extension mapping. Common cost: ingestion supplies the root;
frontends associate assertions with it. The current evidence is fixture-scoped
and unversioned.

### `file`

An independently addressable source unit presented to analysis, including a
generated or virtual unit whose origin is recorded. A retrieval window within
a source unit is not a file.

**Admission result.** Accepted by
[report 002 section 003](docs/reports/002_consolidated_progress.md#003-core-admission-review). Adequacy: locates entities within a source tree.
Identical meaning: source-unit boundaries do not assert language semantics.
Honest absence: ingestion distinguishes missing source from failure to read it.
Subsidiarity: source location is part of the common query contract. Common cost:
ingestion establishes units and origins; frontends report associations and
limitations. Generated and virtual source origins remain future coverage work,
not a blocker for the kind's core meaning.

Location is a property, not an identity derived from byte or line position.
Renames and moves obey the constitutional identity and provenance rules.

### `definition`

A named or anonymous program construct introduced in source as a semantic unit,
such as a function or type. Its identity is grounded in source-analysis evidence,
not an arbitrary text interval. Naming is a property; lacking a name does not
by itself exclude a construct.

**Admission result.** Accepted by
[report 002 section 003](docs/reports/002_consolidated_progress.md#003-core-admission-review). Adequacy: carries program-entity existence queries.
Identical meaning: the core records the entity; its language-specific kind and
semantics remain in extensions. Honest absence: unknown constructs and missing
identity evidence follow the coverage and identity rules. Subsidiarity: existence
belongs to the common model. Common cost: frontends supply supported constructs
and declare omissions. The current evidence covers named Java and Clojure
fixture constructs; anonymous constructs remain future coverage work, not a
different core meaning.

### `module`

Proposed meaning: a named unit of organization above individual definitions and
within a repository. This meaning is not yet admitted.

**Admission assessment.** Adequacy: potentially groups existence/reference
queries; necessity beyond other containers is unproven. Identical meaning:
unresolved across namespaces, packages, and compilation units. Honest absence:
no language construct and unavailable frontend coverage remain distinguishable.
Subsidiarity: admission must show why extensions and optional mappings are
insufficient. Common cost: frontend coverage assessments are pending. These gaps
block `module` and `IMPORTS`. They are independent of the settled `CONTAINS` /
`DEFINES` split, which is about direct containment and definition introduction
rather than module semantics.

## Relationship Definitions

### `CONTAINS`

Relates a source or program container to an entity directly contained in it. It
is direct containment, not transitive reachability, and it does not by itself
assert that the target is a program definition. The initial admitted evidence is
source ingestion asserting that a repository contains a file.

**Admission result.** Accepted by
[report 002 section 004](docs/reports/002_consolidated_progress.md#004-defines-and-contains-split). Adequacy: answers
where source and program entities sit without forcing every contained entity to
be a definition. Identical meaning: direct containment is the same source
organization claim for Java and Clojure fixtures, and future program-containment
uses must supply their own evidence. Honest absence: unknown containment remains
unavailable or unresolved rather than invented. Subsidiarity: source-tree
membership is a common graph question and cannot live in a language extension.
Common cost: source ingestion supplies the initial repository-to-file evidence.

### `DEFINES`

Relates a source or program container to a program definition introduced
directly within it. It is definition introduction, not general containment and
not transitive reachability. A repository containing a file is `CONTAINS`, not
`DEFINES`, because a file is a source container rather than a program definition.

**Admission result.** Accepted by
[report 002 section 004](docs/reports/002_consolidated_progress.md#004-defines-and-contains-split). Adequacy: answers
where a program definition is introduced. Identical meaning: the shared relation
does not encode Java class membership, Clojure namespace forms, or language
scope rules; those details remain in frontend extensions and evidence. Honest
absence: an unsupported or unresolved introduction cannot be presented as a
fact. Subsidiarity: consumers need the common question "which definitions are
introduced directly by this container" without knowing the language family.
Common cost: the current Java and Clojure frontends already supply direct
introduction evidence for fixture-scoped definitions.

### `REFERENCES`

Relates an entity to another entity it names or otherwise designates, without
claiming what the reference does. Endpoints retain their admitted kinds;
language-specific meaning is not rewritten into a generic kind.

**Admission result.** Accepted by
[report 002 section 003](docs/reports/002_consolidated_progress.md#003-core-admission-review). Adequacy: carries the common reference question.
Identical meaning: designation does not prescribe call, read, or dispatch
semantics. Honest absence: confirmed absence, unresolved targets, and unavailable
analysis remain distinct. Subsidiarity: the common reference query cannot depend
on a language-pair mapping. Common cost: frontends record supported references
with evidence and declare omissions. The initial endpoint set is `definition`;
future endpoint expansion is additive admission work.

A fully established `A REFERENCES B` is a fact even when the frontend cannot
distinguish a call from a read. If the target is unresolved, it is a partially
resolved assertion. Relationship specificity and resolution are different.

### `CALLS`

A reference that invokes the referenced definition. Language-specific dispatch
semantics remain in extensions.

**Admission result.** Accepted by
[report 002 section 003](docs/reports/002_consolidated_progress.md#003-core-admission-review). Adequacy: specializes the common reference query.
Identical meaning: invocation needs evidence independent of dispatch mechanism.
Honest absence: no invocation construct differs from unavailable call analysis.
Subsidiarity: a common invocation query needs justification across declared
languages, not just one pair. Common cost: frontends supply invocation evidence
or report unavailable coverage. The accepted meaning is invocation evidence, not
complete dispatch resolution.

The proposed query contract includes calls when asking for all references.
One occurrence is counted once in that query, even if storage records both a
general reference and a specialized call. A calls-only query counts invocation
occurrences. Per-kind measurements use the relevant expected set; counts of
overlapping kinds are not added to infer a total. Storage encoding remains
schema work.

### `IMPORTS`

Proposed meaning: relates a file or module to another module it makes available
for reference. Because the target kind is not admitted, this definition is
blocked too.

**Admission assessment.** Adequacy: potentially exposes availability across
units. Identical meaning: pending a module definition and common availability
semantics. Honest absence: unsupported analysis must not look like no imports.
Subsidiarity: admission must demonstrate a common question beyond pair-specific
mappings. Common cost: frontend coverage and conformance fixtures are pending.

Availability does not itself establish what becomes invalid after an edit.
Fine-grained invalidation belongs to the invalidation requirements in
[SPEC.md](SPEC.md) and to language extensions. Textual inclusion
is not automatically an import or a merge discarding the included file's
identity. Inclusion assertions retain provenance; whether they establish this
proposed availability relation remains an admission question.

## Remaining Admission Questions

1. Establish a common `module` meaning, or reject it. `IMPORTS` depends on the
   outcome. Organization remains expressible in extensions either way.
2. Establish whether textual inclusion satisfies the accepted import meaning.
   This blocks the relevant `IMPORTS` coverage until resolved, not unrelated
   ingestion or reference analysis.
3. Publish an explicit semantic contract version and coverage matrix when a
   consumer-facing contract exists. The initial accepted roster is unversioned
   implementation guidance until then.

The former container/entity question is settled in Defined Terms. The former
`DEFINES` ambiguity is settled by the `CONTAINS` / `DEFINES` split above. The
former call/reference overlap question is settled by the proposed
occurrence-counting contract above; its physical encoding remains schema work.
