---
title: "Shared-core roster"
doc_type: "specification"
lifecycle: "active"
status: "draft"
agent_action: "reference_for_context"
updated: "2026-09-13"
---

# semidx Shared Core

The proposed shared-core kinds and their admission assessments. No roster
version has been accepted or published. Every kind below is a candidate, not an
available runtime capability or an immutable contract.

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

## Candidate Status

| Kind | Status | Dependencies | Remaining admission work |
| --- | --- | --- | --- |
| `repository` | Candidate | None | Coverage and conformance evidence |
| `file` | Candidate | `repository` | Coverage and conformance evidence |
| `definition` | Candidate | None | Coverage and conformance evidence |
| `module` | Blocked candidate | None | Common meaning and frontend coverage |
| `DEFINES` | Candidate | Any admitted container kind, `definition` | Containment evidence for the declared coverage |
| `REFERENCES` | Candidate | Admitted endpoint kinds | Coverage, resolution, and query evidence |
| `CALLS` | Candidate | `definition`, `REFERENCES` | Invocation and reference-inclusion evidence |
| `IMPORTS` | Blocked candidate | `file`, `module` | Module admission and import semantics |

Source containers are entities under the constitution's Defined Terms. Source
ingestion produces their assertions with its actual provenance. Their
architectural status is settled; particular kinds still require admission.

## Proposed Entity Definitions

### `repository`

The root source container for one indexed source tree. Every entity belongs to
one such indexing scope. This does not assert a particular version-control
system, source layout, or module structure.

**Admission assessment.** Adequacy: scopes existence/reference queries.
Identical meaning: source-tree membership is independent of language.
Honest absence: ingestion must establish a root for a successful index; failure
is an error, not absence. Subsidiarity: a common query scope cannot depend on an
optional pairwise extension mapping. Common cost: ingestion supplies the root;
frontends associate assertions with it. Conformance evidence is pending.

### `file`

An independently addressable source unit presented to analysis, including a
generated or virtual unit whose origin is recorded. A retrieval window within
a source unit is not a file.

**Admission assessment.** Adequacy: locates entities within a source tree.
Identical meaning: source-unit boundaries do not assert language semantics.
Honest absence: ingestion distinguishes missing source from failure to read it.
Subsidiarity: source location is part of the common query contract. Common cost:
ingestion establishes units and origins; frontends report associations and
limitations. Conformance evidence is pending.

Location is a property, not an identity derived from byte or line position.
Renames and moves obey the constitutional identity and provenance rules.

### `definition`

A named or anonymous program construct introduced in source as a semantic unit,
such as a function or type. Its identity is grounded in source-analysis evidence,
not an arbitrary text interval. Naming is a property; lacking a name does not
by itself exclude a construct.

**Admission assessment.** Adequacy: carries program-entity existence queries.
Identical meaning: the core records the entity; its language-specific kind and
semantics remain in extensions. Honest absence: unknown constructs and missing
identity evidence follow the coverage and identity rules. Subsidiarity: existence
belongs to the common model. Common cost: frontends supply supported constructs
and declare omissions. Coverage and conformance evidence are pending.

### `module`

Proposed meaning: a named unit of organization above individual definitions and
within a repository. This meaning is not yet admitted.

**Admission assessment.** Adequacy: potentially groups existence/reference
queries; necessity beyond other containers is unproven. Identical meaning:
unresolved across namespaces, packages, and compilation units. Honest absence:
no language construct and unavailable frontend coverage remain distinguishable.
Subsidiarity: admission must show why extensions and optional mappings are
insufficient. Common cost: frontend coverage assessments are pending. These gaps
block `module` and `IMPORTS`. They do not block `DEFINES`, whose container
endpoint ranges over whichever container kinds are admitted.

## Proposed Relationship Definitions

### `DEFINES`

Relates a source or program container to a definition introduced directly within
it. It is direct containment, not transitive reachability. Its container endpoint
ranges over whichever container kinds are admitted. None is admitted yet; the
current container candidates are `repository`, `file`, `definition`, and
`module`. Admitting a container kind extends this relationship additively rather
than redefining it, so an unadmitted container candidate does not block it.

**Admission assessment.** Adequacy: answers where an entity is introduced.
Identical meaning: direct containment needs evidence without replacing language
scope rules. Honest absence: unknown containment is unresolved or unavailable,
not invented. Subsidiarity: common containment needs justification independent
of language-specific organization. Common cost: frontends need containment
evidence for declared coverage. Admission awaits containment fixtures.

### `REFERENCES`

Relates an entity to another entity it names or otherwise designates, without
claiming what the reference does. Endpoints retain their admitted kinds;
language-specific meaning is not rewritten into a generic kind.

**Admission assessment.** Adequacy: carries the common reference question.
Identical meaning: designation does not prescribe call, read, or dispatch
semantics. Honest absence: confirmed absence, unresolved targets, and unavailable
analysis remain distinct. Subsidiarity: the common reference query cannot depend
on a language-pair mapping. Common cost: frontends record supported references
with evidence and declare omissions. Coverage and query fixtures are pending.

A fully established `A REFERENCES B` is a fact even when the frontend cannot
distinguish a call from a read. If the target is unresolved, it is a partially
resolved assertion. Relationship specificity and resolution are different.

### `CALLS`

A reference that invokes the referenced definition. Language-specific dispatch
semantics remain in extensions.

**Admission assessment.** Adequacy: specializes the common reference query.
Identical meaning: invocation needs evidence independent of dispatch mechanism.
Honest absence: no invocation construct differs from unavailable call analysis.
Subsidiarity: a common invocation query needs justification across declared
languages, not just one pair. Common cost: frontends supply invocation evidence
or report unavailable coverage. Conformance fixtures are pending.

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
   outcome; `DEFINES` no longer does. Organization remains expressible in
   extensions either way.
2. Establish whether textual inclusion satisfies the accepted import meaning.
   This blocks the relevant `IMPORTS` coverage until resolved, not unrelated
   ingestion or reference analysis.
3. Choose initial language/frontend coverage and provide admission fixtures and
   expected query sets. Until then the roster remains a proposal.

The former container/entity question is settled in Defined Terms. The former
call/reference overlap question is settled by the proposed occurrence-counting
contract above; its physical encoding remains schema work.
