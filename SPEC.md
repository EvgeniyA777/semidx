---
title: "Companion requirements"
doc_type: "specification"
lifecycle: "active"
status: "draft"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# semidx Requirements

The companion requirements document named by role in
[ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md). This is a draft
requirements entry point, not a complete implementation specification or a
published runtime contract. Document ownership is recorded in the
[documentation policy](docs/agent-policy/documentation.md). The architecture
rationale lives in [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md), and
reviewable checks live in [CONFORMANCE.md](CONFORMANCE.md).

## Core Contract Lifecycle

[CORE.md](CORE.md) owns the kinds, definitions, and admission evidence. A
candidate has no published-contract status: it may be edited, replaced, or
rejected. Acceptance requires all constitutional admission requirements,
resolved transitive dependencies, declared frontend coverage, and conformance
fixtures. An accepted definition is not evidence of implemented support.

A published roster has an explicit version identifying the accepted definitions
and a published coverage matrix. Every snapshot and query contract must identify
the semantic contract version it uses. Historical definitions remain available
so old assertions retain their original interpretation.

Corrections to membership or meaning require a new contract version and a
migration record. That record names the affected kinds and consumers, explains
the defect and replacement, and specifies conversion or reanalysis, identity
handling, deprecation, compatibility, and retirement conditions. A conversion
must not claim semantic equivalence it cannot establish. Version mismatches and
unsupported versions produce explicit results, never silent reinterpretation.

An erroneous kind may be absent from a corrected roster; consumers using that
roster must be able to observe the change. Retiring support for an old version
does not erase its definition or silently relabel its assertions. Exact version
encoding and compatibility windows remain requirements to settle before the
first contract publication.

## Core Admission Criteria

[CORE.md](CORE.md) assesses every candidate against the five criteria below.
They were constitutional text before the constitution was distilled to product
identity. Admission mechanics are changeable requirements, so they live here; the
constitutional boundary they serve is
[section 6](ARCHITECTURE_CONSTITUTION.md#6-language-frontends-preserve-meaning).

**Adequacy.** The core must be sufficient for a consumer to ask, across
languages, what entities exist and what refers to what. A core that cannot carry
existence and reference does not make frontends comparable, which is the only
reason it exists. This is a floor on the accepted roster, not on any one
candidate: a candidate carrying it may be replaced by a better definition, but it
cannot simply be rejected and leave the floor unmet.

**Identical meaning.** A kind may be core only if it means the same thing in
every supported language. This is a test of meaning, not of presence. A kind may
satisfy it even where some language has no instances of that kind; it must also
satisfy the other criteria.

**Honest absence.** A frontend produces a core kind only where its language
actually has one. Confirmed absence, absence of the construct from the language,
and inability of the frontend to analyze that construct must remain
distinguishable to consumers. A frontend must never substitute an approximation
for a core kind it cannot produce. A language whose frontend cannot produce some
core kind is supported with that coverage reported unavailable, not excluded.

**Subsidiarity.** A kind may be core only when the cross-language question it
answers is well-posed for every supported language and belongs to the guaranteed
common model. A question confined to particular languages is answered by a
declared mapping between those languages' extensions. The ability to map one
pair does not disqualify a kind the common model needs. Requiring every language
to map toward one common target is a core kind in disguise and is governed as
one.

**Common cost.** Adding a core kind obliges every existing frontend to conform to
its definition when producing it and to declare its coverage. It does not require
a frontend to extract an unsupported construct. The core therefore does not grow
casually: each addition requires a conformance and coverage assessment across
frontends, with limitations exposed through the capability matrix.

A candidate is accepted only when all five criteria are assessed, its transitive
dependencies are resolved, its frontend coverage is declared, and its conformance
fixtures exist.

## Coverage And Conformance

The capability matrix identifies language, producer version, entity and
relationship coverage, and identity limitations, including source ingestion.
It distinguishes a construct
absent from a language, unavailable frontend analysis, and confirmed absence in
an analyzed source snapshot. Analysis failures are reported separately.

For each supported kind, fixtures must establish admission meaning and expected
facts, partially resolved assertions, and approximate assertions. Reference
query fixtures include specialized relationships such as calls without counting
the same occurrence twice. Resolution evidence and mapping provenance remain
visible through every public surface.

Conformance scenario families are owned by
[CONFORMANCE.md](CONFORMANCE.md#required-scenario-families). Requirements that
adopt one of those checks specify concrete fixtures, commands, expected results,
and publication gates here or in subordinate specifications.

A first in-memory implementation slice exists
([plan](docs/plans/001_zig_vertical_slice.md),
[evidence](docs/reports/001_zig_vertical_slice_progress.md)), with fixture
coverage for two languages. There is still no capability matrix, no executable
conformance suite, and no published coverage. The requirements above remain
requirements for later verification, not claims of passing results.

The repository-scale ingestion slice is also complete
([plan](docs/plans/002_repository_scale_ingestion.md),
[evidence](docs/reports/002_consolidated_progress.md#005-repository-scale-ingestion-progress)). It
settles the first source-identity layer for implementation guidance: discovered
source units have allocated identity, path is a property, exact moves preserve
unit and contained entity identities, ambiguous or unsupported moves are
reported, and move-plus-edit remains identity loss until stronger evidence
exists. It also added the dependency propagation mechanism cross-unit facts
need, before any producer declared dependencies.

The first cross-unit producer is implemented
([ADR 004](docs/adr/004_allow_java_same_package_type_resolution.md),
[plan](docs/plans/003_java_package_type_resolution.md),
[evidence](docs/reports/003_java_package_type_resolution_progress.md)). A Java
simple type name in a unit with an explicit package can be a `REFERENCES` fact
targeting the one current top-level class another unit declares in that package,
once the Java frontend has ruled out every scope Java gives precedence over the
package. The dependent declares a dependency on the provider unit, and a change
to a package's exported classes reanalyzes that package's other units. This is
implementation guidance for one Java rule, not a Java coverage claim: it admits
no `module` or `IMPORTS`, publishes no contract or capability matrix, and treats
the indexed repository as a single Java classpath.

## Requirements Still To Specify

| Area | Work needed before the dependent implementation or publication |
| --- | --- |
| Implementation stack | Settled for the first slice: Zig ([ADR 001](docs/adr/001_choose_zig_implementation_language.md)), `zig build`, and local tree-sitter C sources ([ADR 002](docs/adr/002_local_tree_sitter_parser_dependency.md)). Packaging, distribution, and any long-running process mode remain to specify |
| Initial coverage | Target languages, producer versions, admission fixtures, and measured limitations |
| Core roster | Resolve the blocked candidates and admission evidence in CORE.md |
| Extensions and mappings | Per-language definitions, declared mapping semantics, and evidence preservation |
| Source identity | Discovered roots, source-unit identity, path-as-property, tombstones, and exact move correspondence are implemented for the in-memory slice. Still to specify: generated or virtual source origins, multi-root identity, and stronger evidence for move-plus-edit refactors |
| Storage and snapshots | Representation, atomic publication, persistence, and contract-version encoding |
| Public contracts | Schemas, resolution encoding, errors, ordering, pagination, and transport parity |
| Invalidation | Unit-to-unit dependency propagation and Java package-export invalidation exist, with Java same-package type resolution as the first producer. Still to specify: further language-correct producers, name-grained or aspect-grained invalidation, and build-module or classpath boundaries for package scope |
| Local budgets | Discovery has initial file-size, unit-count, and depth budgets with diagnostics; repository-scale tests guard affected-region work. Still to specify: benchmark repositories, memory/startup budgets, and publish/query cost budgets |
| Optional outbound data | Destination/data consent settings and verification for projections and diagnostics |

## Proposed Delivery Direction

Delivery can progress from structural entities and program relationships to
finer dependency and impact analysis, then compilation-related consumers. This
is a proposal, not a mandated sequence or an authorization to implement it.
Incremental maintenance, consistent snapshots, identity, and the other
constitutional properties apply to the first working graph; they are not a later
phase.

Search, agents, MCP, documentation linkage, and IDE integrations may develop
alongside that work. A concrete execution plan must first satisfy the repository
Plan Readiness Gate.
