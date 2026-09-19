---
title: "Project glossary"
doc_type: "reference"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-19"
---

# semidx Glossary

The canonical vocabulary of the project: one term, one meaning, used the same
way in documentation and in the implementation.

## What This File Is Not

This file is not normative. It has no version, no amendment procedure, and no
authority over architecture. It records what words mean so that the documents
which *do* constrain the architecture can be read precisely. It is expected to
grow and change as the project learns.

Five terms are deliberately absent. `entity`, `node`, `relationship`,
`assertion`, and `fact` are defined in
[ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md) under Defined
Terms, because the distinctions they draw are themselves architectural
constraints. Repeating them here would give them two owners. Look them up
there.

## Terms

**analysis context** — Frontend input built from current graph facts and other
analysis-side evidence so a frontend can decide whether a source construct
resolves exactly, stays unresolved, or is outside coverage. Analysis context is
not itself graph authority: only assertions emitted and reconciled into the
graph become observable graph claims.

**capability matrix** — The published statement of what `semidx` can and cannot
analyze, per language, producer version, and entity or relationship kind,
including identity limitations of frontends and source ingestion. It exists so
partial coverage is visible to consumers rather than hidden behind a
uniform-looking graph.

**class shape** — The part of a class other units' analysis depends on, as
distinct from the class's existence: its current declared member set, the access
of those members within a frontend's covered rules, and whether it declares
supertypes. It is not a graph kind and not an inheritance model; it names which
provider changes oblige a dependent unit to be reanalyzed. What counts as class
shape for a given language is owned by that language's ADR and reported in the
[capability matrix](docs/spec/capability_matrix.md); this entry records the
concept, not the roster.

**consumer** — Anything that reads the graph rather than producing it: search,
AI agents, IDE integration, impact analysis, documentation linkage, or future
compilation tooling. The direction is the point: consumers depend on the graph,
never the reverse.

**containment** — A direct parent-child claim that one entity is immediately
inside another source or program container. It describes source organization or
program nesting, not by itself the introduction of a program definition. For
example, a repository containing a file is containment.

**content identity** — Evidence that two observed source-unit contents are the
same bytes, currently recorded as a SHA-256 value. It is evidence used by
source-unit correspondence; it is not a semantic identity by itself.

**covered** — Inside a producer's currently implemented exact rules. A covered
construct, shape, or rule is one the producer can decide exactly today; anything
outside it stays unsupported or unresolved, and those answers stay
distinguishable from each other. Covered is therefore a claim about a producer's
present reach rather than about the language, it changes as frontends grow, and
what it currently reaches per language is reported in the
[capability matrix](docs/spec/capability_matrix.md).

**dependency declaration** — A record that one source unit's analysis read
something about another source unit. A change to the provider obliges the
dependent to be reanalyzed. The record says nothing by itself about import
semantics, module membership, or program availability.

**dependent source unit** — A source unit whose analysis result declared that it
read information supplied by another source unit. When the provider changes, the
dependent is a candidate for reanalysis even if its own bytes did not change.

**definition introduction** — A narrower claim that a container directly
introduces a program definition. For example, a file may introduce a class,
namespace, function, or variable definition, and a class may introduce a method.
This is intentionally distinct from containment: a repository containing a file
does not by itself introduce the file as a program definition. Relationship
names and admission status are owned by [CORE.md](CORE.md).

**detail level** — A preview-tool output mode that controls how much graph
detail a consumer asks for. Detail levels may change the shape and size of an
experimental consumer response, but they do not change the semantic model or the
resolution of any assertion.

**dogfood** — Evidence gathered by running `semidx` on this repository or a
temporary copy of it. Dogfood checks are useful because they exercise real
project patterns, but they are still evidence for the current implementation,
not a broad language-support claim.

**edge** — The graph's representation of a relationship. Use it only where the
representation itself is the subject; the relationship is the thing being
modeled, the edge is how it is stored.

**evidence text** — Bounded source text recorded with an assertion as evidence
for what the producer observed, such as a name or callee. MCP output omits it by
default; enabling it is separate from returning arbitrary source bodies.

**extension label** — A language-specific key and value a frontend attaches to
an entity or assertion it establishes, such as a construct kind or a package
name. A label is part of what the producer recorded, so it is graph content a
later analysis may read back — unlike a *projection*, which carries no
authority. Labels are how language-specific meaning stays out of the shared
core; the per-language roster is reported in the
[capability matrix](docs/spec/capability_matrix.md), and the catalogue itself is
owned by [SPEC.md](SPEC.md).

**external target** — A relationship target entity that was established outside
the source unit currently being analyzed and supplied to the frontend through
analysis context. Reconciliation must still validate that the target is current,
compatible with the relationship kind, and backed by a dependency declaration.

**fingerprint** — One possible mechanism for recognizing that some aspect of an
entity's meaning changed. A future design may use semantic revisions,
dependency generations, change epochs, or another mechanism instead. The
requirement is the semantic ability to distinguish changes that matter
differently, not this word.

**freshness** — Whether an assertion was established about the current contents
of the source unit it was observed in. It is a separate axis from *resolution
level*, and collapsing the two loses information in both directions: a fully
resolved fact about source that has since changed is still a fact about what its
producer read and still not current, while an unresolved assertion about the
contents on disk right now is current and still unresolved.

**frontend** — A language-specific component that produces assertions about
source code for the model: a parser, a Tree-sitter grammar, a SCIP indexer, a
compiler API, a language server, a static analyzer, or a custom extractor.
Frontends differ in coverage and in how much they resolve. They do not define
the model they feed.

**habit loop** — The repeatable local agent workflow for using the MCP preview:
start with graph-backed orientation, follow focused definition or context calls,
read exact files only where needed, and refresh after edits before trusting new
graph answers.

**identity correspondence** — Evidence that an entity or source unit observed
before and after a change is the same semantic thing. Exact correspondence may
be recorded as established; heuristic evidence may be recorded only without
pretending it is a fact.

**identity event** — A recorded outcome of reconciliation for an entity or
source unit, such as preserved, created, removed, or lost. It makes identity
preservation or identity loss observable instead of hiding it as an unrelated
delete/create sequence.

**import alias** — Frontend-local evidence that a source-language alias refers
to an imported source unit or package under a frontend's covered rules. An
import alias is not a graph relationship by itself and does not admit `IMPORTS`
or `module`; those candidates are owned by [CORE.md](CORE.md).

**invalidation** — The process of deciding which source units must be
reanalyzed because a source change may affect assertions they previously
produced. Invalidation is driven by changed contents, dependency declarations,
and producer-specific channels, of which Java package exports are the first. A
producer-specific channel is needed exactly where an earlier answer was
unresolved and so declared no dependency to propagate along; the roster of
channels therefore grows with the producers that need one, and which channels
are specified is owned by [SPEC.md](SPEC.md). *Reader hints* are how a channel
finds the units it owes.

**local MCP preview** — The experimental local stdio MCP consumer over published
graph snapshots. It is a preview tool surface, not a published semantic
contract, and it does not define graph semantics.

**projection** — A derived view that is not a source of truth: a lexical index,
a vector index, an embedding window, a rendered snippet, a rendered subgraph, or
an analyzer-side candidate table such as a package, member, or hint lookup. A
projection may be derived from the graph or built directly from source text.
Either way it can be rebuilt or discarded without losing graph meaning, and
either way it may discover, rank, or render — never establish a program
relationship. *Analysis context* is what a projection hands one frontend for one
source unit: the projection is the table, the context is the answer read out of
it, and neither carries authority.

**provenance** — The record of what produced an assertion: source ingestion, a
frontend, an analyzer, exact system resolution, or another recorded method.

**provider source unit** — A source unit whose current graph facts were read by
another unit's analysis. Provider changes can invalidate dependents through
dependency declarations or producer-specific export tracking.

**reader hint** — A conservative record of which source units may read some
piece of another unit's evidence, kept by a projection so that a change to that
evidence can reach a unit whose earlier answer declared no dependency, because
an unresolved answer read no provider. A hint may be a superset: reanalyzing a
unit that no longer reads the evidence costs a pass and changes no claim.
Under-inclusion is a freshness defect, over-inclusion is only a cost, and the
asymmetry is deliberate.

**reason family** — The class an explanation of a negative answer belongs to,
such as no source, out of scope, ambiguous, overloaded, or outside covered
shapes. Tests and measurements assert the family so that the wording of an
explanation can improve without reading as a regression, while a change of
family stays a change of meaning.

**release candidate** — A repository state that has passed the named local gate
for a planned release but has not necessarily been tagged or distributed.

**release gate** — The documented set of verification commands, runtime smoke
checks, documentation checks, and residual-risk review required before a release
or preview handoff may be considered ready.

**resolution level** — How far an assertion's semantic claim was established.
The categories are constitutionally distinct; the concrete enumerated values and
their encoding are schema requirements owned by [SPEC.md](SPEC.md).

**response budget** — A preview-tool constraint on response size or shape,
expressed through item limits, detail levels, include flags, and explicit
metadata rather than by cutting JSON bytes. Response budgets keep consumer
context usable without changing graph authority.

**semantic contract** — A future published promise about the semantic model,
schema shape, capability matrix, and migration behavior exposed to consumers.
The current preview reports `semantic_contract_version: null`; publication and
migration procedures are owned by [SPEC.md](SPEC.md).

**snapshot** — One consistent state of the graph: the state a query is answered
against. A consumer never observes a graph assembled from more than one
snapshot.

**source-derived graph values** — Paths, names, designators, ranges, ids,
diagnostic messages, and other values returned from the graph that are derived
from local source without being source text. Sending them to a hosted consumer is
still outbound source-derived data and requires the user's configured
destination and consent boundary.

**source ingestion** — The producer path that discovers source units and records
source-organization facts such as repository/file entities and containment. It
does not by itself establish program relationships.

**source text** — The literal contents of source files or snippets from them.
Source text is distinct from source-derived graph values and from bounded
evidence text.

**source unit** — An independently addressable source input presented to
analysis, such as a discovered file. Its identity is allocated by the graph and
is not its path; path is a property that can change.

**source-unit registry** — The graph-maintained table of known source units,
their allocated ids, current paths, language, content identity, tombstone state,
and correspondence evidence across rescans.

**stale** — The state of a source unit whose contents changed without a
successful reanalysis, and of the assertions that describe its earlier contents.
A stale unit is not an empty one: withdrawing its assertions would claim an
absence nothing observed, and presenting them as current would claim they
describe source that is no longer there. They stay recorded, stay attributed,
and stop answering queries that did not ask for them.

**symbol** — A named entity, one a frontend can address by a stable name. A
symbol is a subset of entities: anonymous constructs are entities but not
symbols.

**tool schema** — A consumer-interface schema that advertises the accepted
arguments for an experimental tool surface such as MCP. Tool schemas describe
how to ask for graph projections; they are not semantic schemas and do not
define graph meaning.

**truncation** — An explicit report that a bounded result omitted additional
items. Truncation must say which result set was bounded and preserve enough
metadata for the consumer to decide whether to make a narrower or more detailed
follow-up query.

**work bound** — A deterministic assertion about how much work an operation
inspects — candidates, records, or propagation rounds — committed as a test
rather than as a wall-clock threshold. It is chosen because it fails under the
access path it replaced and stays reliable on any machine, which a timing
threshold does not. Wall-clock measurements remain useful as observations of
what users feel; they are not the committed bound.

## Document Ownership

The [documentation policy](docs/agent-policy/documentation.md#canonical-ownership)
maps the constitutional document roles to their current files. The rationale is
in [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md); the core roster is in
[CORE.md](CORE.md); requirements and schema vocabulary are in [SPEC.md](SPEC.md);
and conformance scenario families are in [CONFORMANCE.md](CONFORMANCE.md).
Conceptual vocabulary stays here.
