# semidx — Architecture Constitution

**Status: DRAFT — not ratified.** See §18 for ratification and immutability.

## Scope Of This Document

This document fixes the identity of `semidx`: the properties whose removal would
make the project something else rather than a later version of the same thing.

It deliberately avoids numbers, field names, file names, schemas, algorithms,
storage layouts, test fixtures, delivery order, language coverage, and process
mechanics. Those are concrete requirements. They are expected to change as the
project learns, and they belong in companion documents whose names and structure
can change without redefining the product.

The test for whether a statement belongs here is:

> If the opposite were true, while the project still had a semantic graph,
> exactness, identity, incrementality, language frontends, consumer independence,
> and local operation, would it still be `semidx`?

If yes, the statement belongs outside this document.

## Normative Language

The words **must**, **must never**, and **may** express obligations,
prohibitions, and permissions, including when capitalized.

* **must**, **must never** — an obligation or prohibition. A violation is an
  architectural defect, not a trade-off.
* **may** — a permission granted to the implementation. It never means that an
  obligation applies only when convenient.

This document does not give advice. Requirements that are important but not
identity-defining belong outside the constitution.

## Defined Terms

Five terms are defined here, and only five. Each earns its place because the
distinction it draws is itself constitutional.

| Term | Meaning |
| --- | --- |
| **semantic entity**, **entity** | A program construct or source container represented by the model. A source container represents source organization, not an arbitrary text segment selected for retrieval. |
| **node** | The graph's representation of an entity. |
| **relationship** | A semantic connection between entities. |
| **assertion** | Anything the graph records: entity existence, relationship existence, relationship target, identity correspondence, or another semantic claim. |
| **fact** | An assertion fully established by source ingestion about source organization, by a language frontend about program meaning, or by exact system resolution over such assertions. A fact is a kind of assertion. Not every assertion is a fact. |

Using **fact** where **assertion** is meant asserts resolution that may not
exist, and is the failure §3 forbids.

## 1. Semantic Graph Is The Product

`semidx` is an incrementally maintained semantic graph of a codebase.

The semantic graph is the source of truth.

Search, vector embeddings, RAG, MCP, agent context, navigation, impact analysis,
and future compilation tooling may exist.

A text-derived or approximate mechanism may discover candidates, rank them, and
render located source; it must never establish a program relationship. Every
semantic claim about entities and relationships comes from the graph.

The graph must never exist merely to improve retrieval.

## 2. Nodes Are Entities, Not Chunks

Nodes represent semantic entities, not arbitrary chunks of text.

A chunk is defined by where text was cut. An entity is defined by source
organization or program meaning. Text ranges, embedding windows, retrieval
chunks, and display snippets may be attached to entities as projections, but
they must never become graph nodes in their own right.

If nodes are chunks, stable identity, exact relationships, and incremental
maintenance all collapse together.

## 3. Exact, Unresolved, And Approximate Knowledge Stay Distinct

The graph must distinguish facts, partially resolved assertions, and approximate
assertions.

A fact is fully established. A partially resolved assertion establishes part of
a semantic claim while leaving a required part unresolved. An approximate
assertion is heuristic, similarity-based, or confidence-based.

Approximate or unresolved assertions must never become indistinguishable from
facts. Every assertion must carry what produced it and how far it was resolved.

Exact means that established assertions are the only assertions presented as
facts. It does not mean complete coverage of every construct or relationship.

## 4. Semantic Identity Survives Edits

A semantic entity must retain a stable identity across edits unless
correspondence genuinely cannot be established.

Changing a function body, moving a declaration, or renaming a file must be
represented as change to the same semantic entity when the entity's
correspondence is established. Identity loss must be observable as identity
loss, not hidden as an unrelated deletion and creation.

Heuristic identity evidence is permitted, but it must not be presented as an
established fact unless it has been exactly resolved under §3.

## 5. Incrementality Is Core

`semidx` must not treat the repository as something that must always be
completely rebuilt.

The graph must be maintainable by applying source changes to an existing
semantic graph, reanalyzing the affected semantic region, and propagating
invalidation where required.

Consumers must observe one consistent graph state per query. A consumer must
never receive a result assembled from a partially updated graph.

How the implementation represents snapshots, revisions, fingerprints,
dependency generations, transactions, or invalidation queues is not fixed here.
The constitutional requirement is the semantic property: incremental
maintenance remains possible and observations are consistent.

## 6. Language Frontends Preserve Meaning

Language frontends contribute assertions to a common semantic model; no frontend
defines that model.

Supported languages must share a common core sufficient for cross-language
questions about what entities exist and what refers to what. That common core
must not flatten language-specific meaning. Semantics that are specific to a
language remain in that language's extensions, with their own vocabulary and
evidence.

Coverage may differ across languages and producers. Confirmed absence,
unsupported language constructs, unavailable analysis, unresolved assertions,
and approximate evidence must remain distinguishable to consumers.

The concrete roster of core kinds, language-extension kinds, mappings,
capability matrices, and publication or migration procedures belongs outside
this document.

## 7. Consumers Do Not Define The Model

Search, RAG, MCP, IDEs, agents, documentation linkage, impact analysis, and
compilation tooling are consumers or projections of the graph.

They may shape public interfaces. They must not shape the semantic model around
their convenience. A semantic answer whose authority comes from a consumer,
retrieval pipeline, protocol shape, or embedding index rather than the graph is
outside the architecture of `semidx`.

## 8. Local Operation Is Required

`semidx` must remain fully operable as a local process with no mandatory
external service.

The graph must answer questions about the developer's current working copy,
including uncommitted edits. A shared service may accelerate work only when the
local process can still build, update, and query the graph without that service.

Building, updating, and querying the graph must not require transmitting source
code or source-derived data outside the local machine. Such transmission,
including by optional consumers and projections, requires explicit user opt-in
for the destination and data involved and is disabled by default.

## 9. Explicit Non-Goals

None of the following is what `semidx` is:

* a code chatbot;
* a generic RAG framework;
* a vector database;
* a repository-wide grep replacement;
* an IDE;
* a compiler;
* a documentation generator.

`semidx` may support any of them as consumers or projections. It stops being
`semidx` when one of them becomes the center.

## 10. What Belongs Outside This Document

The following are important requirements, but not constitutional text:

* schemas, field names, wire formats, and public API shapes;
* the core-kind roster and language-extension catalogues;
* capability matrices, accuracy measurements, fixtures, and conformance tests;
* storage layout, snapshot mechanics, identity algorithms, and invalidation
  algorithms;
* fingerprint, revision, epoch, or transaction mechanisms;
* delivery plans, implementation stack, local budgets, and process artifacts.

These documents may be strict. They may contain mandatory requirements and
release gates. Their change is governed by their own lifecycle, not by §18.

## 11. Architectural Decision Test

Before introducing a feature or dependency that changes what the graph contains,
how it is maintained, or what a consumer can rely on, ask:

1. Does it keep the semantic graph as the source of truth?
2. Does it keep nodes as semantic entities rather than retrieval chunks?
3. Does it keep facts, unresolved assertions, and approximate assertions
   distinct and attributable?
4. Does it preserve stable semantic identity across edits?
5. Does it preserve incremental maintenance and consistent observation?
6. Does it preserve language-specific meaning while contributing to the common
   core?
7. Does it keep consumers, projections, and protocols from defining the model?
8. Does it preserve local operation without mandatory source-data transmission?

A change that fails this test must not be merged as `semidx`.

## 12. Open Constitutional Questions

**None.**

While this document is DRAFT, any unresolved question about product identity is
recorded here and blocks ratification until closed.

After ratification this section records no open questions. A question not
settled by this constitution is resolved in companion requirements and ADRs only
if the resolution complies with every clause as written. A resolution that
conflicts with a clause requires the fork described in §18.

## 13. Definition Of semidx

The canonical one-sentence definition of the project is:

> **semidx is an incrementally maintained semantic graph of a codebase that
> provides exact program relationships as a foundation for search, AI context,
> navigation, impact analysis, and future incremental analysis and compilation
> tooling.**

All architectural decisions must remain compatible with this definition.

## 14. Rationale Is Not Constraint

The rationale for these constraints is part of the project's design record, but
it is not itself the frozen definition of the product.

Rationale may explain why a clause exists, what failure it prevents, and why an
older draft used stronger or more specific wording. It must not add new
constitutional obligations after ratification.

## 15. Conformance Is Not Constitution

Conformance material turns the constitution into executable or reviewable
checks: fixtures, measurements, traffic observation, snapshot tests, contract
checks, and process gates.

Those checks are mandatory when adopted by the companion requirements, but their
mechanics are not frozen here. A better way to verify the same constitutional
property must remain available without forking the project.

## 16. Drafting Discipline

While DRAFT, this file may be edited freely, but only to better capture the
identity of the project.

Adding a statement here because it is important is not enough. It belongs here
only when losing it would make `semidx` a different product.

## 17. Reserved

This section intentionally carries no independent rule. It preserves stable
section numbering during the draft distillation.

## 18. Ratification And Immutability

### Draft

While the status line reads DRAFT, text may change freely. Ratification is the
act of setting that status line to RATIFIED with a date. It requires §12 to
record no open constitutional questions.

### Ratified

**A ratified document does not change. There is no amendment procedure, and this
section is not the beginning of one.**

Not "changes rarely", not "changes only with justification", not "changes only
by a logged amendment". The file is frozen. No clause is rewritten, relaxed,
strengthened, clarified, renumbered, or reworded. Only a mechanical repair that
touches no sentence — a broken link, a malformed table — is permitted, and it
must be visibly that.

The reason is the purpose of the document. These constraints define what the
product *is*; a build that drops one is a different product. So a constraint
that turns out to be wrong is not an error in the document to be corrected. It
is a discovery that a different product needs to exist.

### When A Constraint Turns Out To Be Wrong

The mechanism for a different product is a different repository. Fork it, write
its own constitution, and let the two projects be what they each are.

Two consequences follow:

* **Getting it right before ratification matters more than getting it written.**
  A frozen constraint that is wrong cannot be fixed in place.
* **The pressure to reinterpret must be refused, not accommodated.** A clause
  that cannot be followed as written is grounds for a fork, not for a generous
  reading.

No log of changes is kept here, because there are no changes to log. The
drafting history lives in `git log`, and durable technical decisions belong in
ADRs.
