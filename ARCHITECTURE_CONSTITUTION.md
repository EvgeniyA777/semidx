# semidx — Architecture Constitution

**Status: DRAFT — not ratified.** This document is being written. Once ratified
it is frozen and never changes; see §18.

## Scope Of This Document

This document fixes what must not change. If one of these constraints is
dropped, the result is a different project, not a later version of this one.

It deliberately contains no numbers, thresholds, field names, formats, language
coverage, schedules, or priorities. Those are concrete requirements: they are
expected to change as the project learns, and they belong in the companion
requirements document (`SPEC.md`), which is versioned and lifecycled
independently.

The test for whether something belongs here rather than in `SPEC.md` is whether
at least two of the following hold:

1. **Irreversibility.** Allowing the opposite for a year would require a
   rewrite, not a refactor.
2. **Project identity.** A build without it would no longer be `semidx`.
3. **Consumer visibility.** It is part of a contract a consumer has already
   relied on and cannot be changed without breaking that consumer.

This document has two states and no others: draft, while it is being written,
and ratified, after which it is frozen permanently. It is never superseded,
never versioned into a series, and never amended. See §18.

## Normative Language

This document uses normative keywords in the sense of RFC 2119. They are used
deliberately, not stylistically.

* **MUST**, **MUST NEVER** — an obligation or a prohibition. A violation is an
  architectural defect, not a trade-off. Exceptions exist only where this
  document names them in a closed list.
* **MAY** — a permission genuinely granted to the implementation. It never means
  that an obligation applies only when convenient.
* **SHOULD** is not used anywhere in this document. A constitution states
  obligations and permissions; it does not give advice. Anything that would be a
  recommendation belongs in `SPEC.md`.

Lower-case `must` and `may` in running prose carry the same force as the
upper-case forms. The document does not distinguish them.

Qualifiers that soften an obligation at the implementation's discretion — "where
practical", "where useful", "whenever possible", "if feasible" — must never
appear in a normative statement here. An obligation with a discretionary escape
clause is not an obligation. Where such a qualifier covered a genuine undecided
question, that question is recorded in §17 instead, to be closed before
ratification.

## Defined Terms

Five terms are defined here, and only five. Each earns its place because the
distinction it draws is itself a constraint: Invariant 2 turns on entity versus
chunk, and §11 turns on assertion versus fact. An obligation written in
undefined words is ambiguous, so these definitions are part of the obligations.

| Term | Meaning |
| --- | --- |
| **semantic entity**, **entity** | A program construct the model represents: a module, a function, a type, a parameter. The canonical word for the modeled thing. |
| **node** | The graph's *representation* of an entity. Used only where representation itself is the subject. |
| **relationship** | A semantic connection between entities: `CALLS`, `USES_TYPE`, `IMPLEMENTS`. The canonical word for the connection. |
| **assertion** | Anything the graph records: that an entity exists, that a relationship exists, what a relationship's target is, that two entities across snapshots are the same entity. Every assertion carries its source and resolution level (§11). |
| **fact** | An assertion that is fully resolved and confirmed by a language frontend. A fact is a kind of assertion. **Not every assertion is a fact** — this is the distinction §11 exists to protect, and the reason the two words are not interchangeable. |

Using **fact** where **assertion** is meant is not a wording slip. It asserts
that something was resolved and confirmed when it may not have been, which is
the failure §11 forbids.

The rest of the project vocabulary — including `frontend`, `snapshot`,
`fingerprint`, `consumer`, `projection`, `symbol`, `edge`, `provenance`,
`resolution level`, and `capability matrix` — is defined in
[GLOSSARY.md](GLOSSARY.md). That file is descriptive and expected to drift,
which is precisely why those terms are not carried here.

## 1. Purpose

`semidx` is an incrementally maintained semantic model of a codebase.

Its primary purpose is to build and maintain an exact, machine-readable semantic graph of source code and its relationships.

The semantic graph is the core product.

Search, vector embeddings, RAG, MCP, agent context, navigation, impact analysis, and future incremental compilation capabilities are consumers or projections of this graph.

They are not the architectural center of the system.

---

## 2. Core Principle

> **The semantic graph is the source of truth. Everything else is an index, projection, interface, or consumer of the graph.**

The architecture must always preserve this rule.

`semidx` must never degrade into:

* a vector database with code chunks;
* a RAG pipeline;
* an enhanced grep tool;
* an embedding search engine;
* an MCP wrapper around textual search.

Those capabilities may exist, but only on top of the semantic model.

---

## 3. Fundamental Model

The system transforms source code into a persistent semantic graph.

```text
Source Code
    │
    ▼
Parsing / Language Analysis
    │
    ▼
Semantic Extraction
    │
    ▼
┌─────────────────────────┐
│     SEMANTIC GRAPH      │
│                         │
│ entities                │
│   symbols, types, ...   │
│ relationships           │
│   calls, references,    │
│   dependencies, ...     │
│ semantic identities     │
└────────────┬────────────┘
             │
    ┌────────┼───────────┬────────────┐
    ▼        ▼           ▼            ▼
 Search    Agents       IDE       Impact Analysis
    │        │                         │
 Vectors    MCP                        ▼
   /RAG                         Incremental Engine
```

The arrows below the semantic graph point outward.

The system must not be designed in reverse, where the graph exists merely to improve retrieval.

---

## 4. Semantic Layers

### L1 — Structural Model

Represents the structural entities extracted from source code.

Examples:

* repository
* module
* file
* namespace
* class
* struct
* enum
* function
* method
* field
* variable
* parameter

This layer answers:

> What entities exist?

---

### L2 — Program Semantic Graph

Represents relationships between semantic entities, each carrying its source and
resolution level (§11).

Examples:

* `DEFINES`
* `REFERENCES`
* `CALLS`
* `IMPORTS`
* `USES_TYPE`
* `RETURNS_TYPE`
* `IMPLEMENTS`
* `OVERRIDES`
* `INSTANTIATES`
* `READS`
* `WRITES`
* `DEPENDS_ON`

This layer answers:

> How are program entities related?

This is the minimum level at which `semidx` becomes the intended product.

---

### L3 — Fine-Grained Dependency Model

Represents the precise nature of semantic dependencies.

Examples:

* depends on symbol existence
* depends on signature
* depends on type
* depends on layout
* depends on constant value
* depends on implementation
* depends on generic instantiation
* depends on compile-time evaluation
* depends on ABI

This layer answers:

> What exactly becomes invalid if this entity changes?

L3 enables future capabilities such as:

* precise impact analysis;
* fine-grained invalidation;
* incremental semantic analysis;
* incremental compilation support.

L3 may be implemented progressively. It must not block delivery of L1 and L2.

---

### Shared Core And Language Extensions

This split cuts across L1, L2, and L3 rather than sitting between them. It fixes
what "shared model" means in Invariant 8.

**The shared core is mandatory.** Every frontend for every supported language
must produce it, and must produce it without flattening anything. The core
therefore contains only what genuinely means the same thing in every supported
language.

Core entity kinds:

* repository
* file
* module
* definition — a named entity, whatever kind of thing it is

Core relationship kinds:

* `DEFINES`
* `REFERENCES`
* `CALLS`
* `IMPORTS`

The core is small on purpose. A kind belongs in it only if every supported
language's frontend can produce it honestly, so each addition raises a bar that
every present and future frontend must clear. A language whose frontend cannot
produce the core is a language `semidx` does not support.

**Language extensions sit above the core and are not shared.** They carry what a
language actually means, and must never be reduced to a core approximation: what
kind of definition something is, types and signatures, dispatch, protocols,
behaviours, inheritance, generics, macro expansion, ABI. Several examples listed
under L2 — `USES_TYPE`, `RETURNS_TYPE`, `IMPLEMENTS`, `OVERRIDES`,
`INSTANTIATES`, `READS`, `WRITES` — are extensions, not core. The catalogue of
extensions belongs in `SPEC.md` and is expected to grow.

**Cross-language queries are answered on the core alone.** A question asked
across languages gets a core answer. A question asked within one language may
use that language's extensions and get a more precise one.

The reason for this shape is *where information is lost*. One universal
vocabulary for all languages loses information at write time: once a frontend
has flattened a multimethod into a generic dispatch relationship, the original is
gone from the graph permanently, and such a vocabulary is inevitably shaped by
whichever language was implemented first. Per-language extensions lose only
convenience at read time: a translation nobody has written yet can be written
later. The first loss is irreversible and contradicts §16. The second is
deferred work.

The core carries the question. Extensions carry the precision.

---

## 5. Stable Semantic Identity

Nodes must represent semantic entities, not text fragments.

A semantic entity must retain a stable identity across edits.

Example:

```text
UserService.login
```

must remain the same semantic entity when its body changes.

Changes must be represented as changes to the properties or relationships of that entity, not as a deletion of the entity followed by the creation of a new one.

Stable identity is required for meaningful incremental updates.

### Permitted Identity Breaks

Identity may be broken only when:

* the entity was genuinely removed from the program;
* no available frontend assertion can distinguish the entity from a sibling —
  for example, two otherwise identical anonymous entities in the same scope;
* the frontend supplies no identity-bearing assertion for that class of entity
  at its current capability level.

**This list is closed.** An identity break for any other reason — implementation
convenience, reindexing strategy, or a frontend being awkward to work with — is
an architectural violation, not an engineering trade-off.

When identity is broken for a permitted reason, the break must be recorded as a
break. It must not be presented as a deletion plus an unrelated creation.

### Identity Claims Are Graph Assertions

A statement that an entity in a new snapshot is the same entity as one in a
previous snapshot is itself an assertion about the program, and is therefore
subject to the Provenance Rule in §11.

Heuristic rename and move detection is permitted. Heuristic rename and move
detection that is indistinguishable from an identity confirmed by a language
frontend is not.

---

## 6. Incrementality Is a Core Property

`semidx` must not treat the repository as something that must always be completely rebuilt.

The intended model is:

```text
existing semantic graph
        +
source change
        ↓
detect affected entities
        ↓
reanalyze affected region
        ↓
update graph
        ↓
propagate invalidation where necessary
```

Incremental maintenance of the semantic model is part of the architecture, not a future optimization added after the system is complete.

### What Is Constitutional Here

Two properties of this model are fixed. The mechanism that provides them is not.

1. **Consistent observation.** A query is answered against one consistent state
   of the graph. A consumer never observes a partially updated graph, and
   "the index is currently rebuilding" must never become a correctness caveat
   that consumers have to reason about.
2. **Terminating propagation.** Invalidation propagation must be a terminating
   computation over a finite set of semantic entities. It must not be a
   traversal made to terminate by an arbitrary runtime cutoff, because a cutoff
   silently converts incomplete invalidation into a wrong graph.

Update granularity, the snapshot and versioning mechanism, storage
representation, and propagation strategy are concrete requirements. They belong
in `SPEC.md` and are expected to change.

---

## 7. Change Awareness

Semantic entities must maintain independent fingerprints for the aspects of
their meaning that the system distinguishes when deciding what to invalidate.

A single whole-entity fingerprint is not sufficient. It collapses "implementation
changed" and "signature changed" into one event, which forces coarse
invalidation and removes the path required by Invariant 7.

Which aspects are fingerprinted, how each is computed, and how many exist per
language are concrete requirements and belong in `SPEC.md`. That fingerprints
are aspect-separated is not negotiable there.

Conceptually:

```text
Function
├── identity
├── source fingerprint
├── signature fingerprint
├── type fingerprint
├── dependency fingerprint
└── implementation fingerprint
```

This allows the system to distinguish:

```text
implementation changed
signature unchanged
```

from:

```text
signature changed
dependent code may be affected
```

The goal is eventually to support fine-grained invalidation rather than file-level invalidation.

---

## 8. Search Is a Projection

`semidx` may provide multiple search mechanisms:

* exact symbol lookup;
* graph traversal;
* lexical search;
* BM25;
* grep;
* vector similarity;
* embeddings;
* hybrid retrieval.

None of these is the source of truth.

For example, vector search may answer:

> Which code is conceptually related to authentication?

After relevant semantic entities are found, the graph's own relationships must answer:

> What calls this function?
> What type does it depend on?
> What will be affected if it changes?

Approximate retrieval discovers candidates.

The semantic graph establishes program relationships.

---

## 9. AI and MCP Are Consumers

AI agents are important consumers of `semidx`, but `semidx` must not be architected specifically as an AI chat backend.

Agents must be able to ask questions such as:

```text
find semantic entity X

show callers of X

show dependencies of X

show transitive impact of changing X

find tests covering X

show documentation connected to X

explain the relevant subgraph around X
```

MCP is an interface to these capabilities.

MCP is not the core architecture.

---

## 10. Language Frontends

Language-specific tools may provide assertions to the semantic model. They
provide facts only where they actually resolved what they asserted; the
distinction is governed by §11.

Possible sources include:

* parsers;
* Tree-sitter;
* SCIP;
* compiler APIs;
* language servers;
* static analyzers;
* custom semantic extractors.

No single frontend defines the internal semantic model.

The internal graph must remain conceptually independent from a specific parser or protocol.

Each frontend produces the shared core defined in §4, plus whatever language
extensions it can support. It does not translate everything it knows into a
common vocabulary — that would discard what it knows. The core is the part that
must be common; the rest stays in the language's own terms.

---

## 11. Exact, Partial, and Approximate Knowledge Must Remain Separate

Every assertion in the graph falls into exactly one of three categories, and the
system must keep them distinct. These are three categories, not two.

Resolved — these, and only these, are **facts**:

```text
A CALLS B
A USES_TYPE C
D IMPLEMENTS E
```

Partially resolved:

```text
A CALLS something named "login" — receiver type unknown
B IMPORTS a module that could not be located
C OVERRIDES a parent symbol that was never resolved
```

Approximate:

```text
A is semantically similar to B
this documentation appears relevant to C
these two code regions have similar meaning
```

Approximate assertions must never silently become facts.

A partially resolved assertion names a real relationship kind but does not
establish its target. It is neither a fact nor a similarity judgement, and it
must not be coerced into either.

Coercing it upward — recording an unresolved call as a resolved `CALLS`
relationship — makes the graph state falsehoods. That is the one thing the word
*exact* in §16 forbids outright.

Discarding it — dropping every unresolved assertion — empties the graph exactly
in the languages where dynamic dispatch dominates, which makes the system
useless where it is needed most.

Both failures are avoided by the same rule.

### Provenance Rule

Every assertion in the graph — that an entity exists, that a relationship
exists, what its target is, that two entities across snapshots are the same
entity — must carry:

* **what produced it** — which frontend, analyzer, or method;
* **how far it was resolved.**

An assertion produced by heuristic, approximate, or partial analysis must never
become indistinguishable from one confirmed by a language frontend. A consumer
must always be able to ask a stronger question than "is this relationship
present" and get an answer.

This distinction is mandatory.

The concrete vocabulary — field names, resolution levels, confidence encoding,
how provenance is exposed on each public surface — is a concrete requirement and
belongs in `SPEC.md`. That every assertion carries source and resolution does
not.

---

## 12. Architectural Invariants

The following rules must remain true throughout development.

Each invariant is stated in four parts:

* **Statement** — the obligation itself.
* **Rationale** — the failure it prevents. Without this, a later reader can see
  the prohibition but not its purpose, and cannot judge whether a proposed
  exception defeats it. Principles erode through exceptions that look local.
* **Implications** — what follows concretely for an implementation.
* **Detection** — how a violation becomes visible. An invariant nobody can
  detect is an honour system, not a constraint.

Most Detection entries describe a check that requires an implementation, which
does not exist yet. They are stated now so that the check is derived from the
invariant rather than invented afterwards to match whatever was built. Two
invariants (10 and 12) are detectable today, because they are properties of the
process rather than of code.

### Invariant 1 — The graph is the center

**Statement.** The semantic graph is the architectural center.

**Rationale.** Every consumer in §3 can be built directly on text more cheaply
than on a graph. If one of them is, it works, it ships, and it becomes what
users depend on — after which the graph is unmaintained weight. The center is
not settled once at the start; it is re-decided every time a feature chooses
what to attach to.

**Implications.** A new capability attaches to the graph, not to source text or
to an index derived directly from source text. When a capability cannot be
expressed over the graph, the correct response is to extend the graph, never to
route around it.

**Detection.** Trace each feature's data path from consumer back to source. A
path that does not pass through the graph is a violation. In code this is a
dependency-direction check: modules implementing consumers must not depend on
parsers or raw source readers.

### Invariant 2 — Nodes are entities, not chunks

**Statement.** Nodes represent semantic entities, not arbitrary chunks of text.

**Rationale.** A chunk is defined by where the text was cut; an entity is
defined by what the program declares. Chunks cannot hold stable identity (§5),
cannot carry aspect-separated fingerprints (§7), and cannot be the endpoint of a
resolved relationship. Admitting chunk nodes does not cost one property — §5,
§6, §7, and §11 become unsatisfiable together.

**Implications.** Every node originates in a frontend assertion about a declared
construct. Text offsets are properties of an entity, never its identity.
Embedding windows, retrieval chunks, and display snippets are projections
attached to entities, not nodes in their own right.

**Detection.** Inspect node construction sites: a node whose identity derives
from byte offsets, line ranges, or a splitting rule is a violation. Testable
directly — reflowing whitespace or moving a declaration within a file must not
change the set of node identities.

### Invariant 3 — Three categories, always attributed

**Statement.** Facts, partially resolved assertions, and approximate assertions are three separate categories, and every assertion carries its source and resolution level (§11).

**Rationale.** Collapsing the categories fails in both directions, and both
failures are severe: upward, the graph states relationships that were never
established, destroying the claim in §16; downward, discarding everything
unresolved empties the graph in exactly the languages where dynamic dispatch
dominates.

**Implications.** Resolution level and source are required fields, not optional
annotations — it must be impossible to record an assertion without them. Every
public surface exposes them. A consumer that wants only facts must be able to
ask for only facts.

**Detection.** At the schema level, attempt to construct an assertion with no
source or resolution; it must be rejected by construction rather than by
convention. At the data level, run a fixture containing known-unresolvable
constructs: the count of partially resolved assertions must be non-zero and
stable, since zero means they are being coerced or dropped.

### Invariant 4 — Vectors are droppable

**Statement.** Vector search is optional. The semantic graph is not.

**Rationale.** This is not a judgement about embeddings as a technology. It
fixes the direction of dependency. The invariant is breached the moment the
graph can no longer be built or queried without the embedding pipeline — at
which point an approximate component has become load-bearing for exact results.

**Implications.** Indexing and every graph query must work with embeddings
disabled. No graph construction step waits on an embedding model. Embeddings
live in a component that can be removed without touching graph code.

**Detection.** Run the full pipeline with vector features disabled. Indexing
must complete and every graph query must return the same answers. Degraded
recall in the discovery step is expected and permitted; a failure, an error, or
a changed graph answer is a violation.

### Invariant 5 — RAG consumes, it does not define

**Statement.** RAG is a consumer of `semidx`, not the definition of `semidx`.

**Rationale.** RAG is the most commercially legible framing of this work, so it
exerts continuous pull. The erosion is not a decision to become a RAG product;
it is the point at which retrieval quality becomes the only measured quality,
after which further investment in the graph can no longer be justified to
anyone, including the author.

**Implications.** No structure exists in the graph solely to improve retrieval
scores. A change justified only by a retrieval metric belongs in the projection
layer (§8), not in the model.

**Detection.** Visible in the metric set rather than the code. If the only
quality routinely measured is retrieval quality, the per-language and
per-relationship-kind measurements required by Invariant 12 are missing, and
this invariant has already eroded regardless of what the architecture diagram
still says.

### Invariant 6 — MCP is an interface

**Statement.** MCP is an interface, not the core.

**Rationale.** Tool-call shapes exert ergonomic pressure on whatever they sit
on. Modelling the graph to fit them is backwards, and it binds the model to a
protocol that will change or be replaced while the graph must outlive it.

**Implications.** The core exposes a surface that MCP adapts to, never the
reverse. No concept in the graph schema is named after, or shaped by, an MCP
tool. At least one non-MCP consumer path stays viable at all times.

**Detection.** Remove the MCP layer; the core must remain fully usable through
another surface. Any graph concept whose name or shape only makes sense in MCP
terms is a violation, and is usually visible in the schema vocabulary alone.

### Invariant 7 — The incremental path stays open

**Statement.** The architecture must preserve a path toward incremental graph maintenance.

**Rationale.** Incrementality has historically not been retrofittable: adding it
later has meant rewriting storage and analysis together. The decisions that
foreclose it are individually harmless-looking — assuming a whole-repository
rebuild, deriving identity from position, fingerprinting at file granularity.
None of them announces itself as the decision that closed the path.

**Implications.** No design step may assume that a full rebuild is an acceptable
answer. Storage must be able to update a region without rewriting the whole
graph. The two properties in §6 hold from the first working version, not from a
later hardening pass.

**Detection.** Reindex after a one-line change and measure the work performed.
Work proportional to repository size rather than to change size means the path
is already gone, whatever the code claims. The measurement is cheap, and it must
exist from the first version precisely because the regression is silent.

### Invariant 8 — Frontends feed the shared core

**Statement.** Every frontend must produce the shared core defined in §4, and must never flatten language-specific meaning into it. Language-specific meaning belongs in extensions above the core. Cross-language queries are answered on the core alone.

**Rationale.** A frontend with a private model makes cross-language questions
impossible and makes its own output unreviewable, because there is no common
definition to check it against. A single universal vocabulary fails in the
opposite direction: it destroys at write time whatever it cannot express, and it
is inevitably shaped by whichever language was implemented first. The core is the
smallest thing that makes frontends comparable without making them lie.

**Implications.** No frontend writes to storage in its own vocabulary. Coverage
and resolution level may differ between frontends; the core they produce may not.
Adding a core kind raises the bar for every existing frontend, so the core does
not grow casually.

**Detection.** Frontends must be replaceable: swapping one frontend for another
covering the same language must change resolution levels and coverage, never the
core shape. Separately, a core relationship kind that some supported language's
frontend cannot produce is a defect in the core's definition, not a gap in that
frontend.

### Invariant 9 — Shortcuts must not damage identity

**Statement.** Architectural shortcuts must not destroy stable semantic identity.

**Rationale.** Identity damage is both silent and unrecoverable. A pseudo-delete
followed by a create produces a graph that looks entirely normal, and once
history has been fragmented that way, no later correction reconstructs it. Every
other kind of shortcut in this system can be paid back; this one cannot.

**Implications.** Identity handling is not a place for expedient fixes. A
shortcut that breaks identity must either fit a permitted break in §5 and be
recorded as a break, or be rejected.

**Detection.** Measure identity churn across consecutive snapshots of a fixture
repository with a known edit sequence: entities that neither changed nor moved
must retain identity across every snapshot. Any unexplained churn is a
violation, and the measurement must be routine, because this failure is
invisible by inspection.

### Invariant 10 — Features carry the burden of proof

**Statement.** A feature that does not strengthen the semantic model or consume it must justify why it belongs in `semidx`.

**Rationale.** Scope creep does not arrive as a bad proposal. It arrives as a
sequence of individually attractive features, each defensible on its own. Without
a standing burden of proof, the centre dissolves by accretion rather than by
decision, and no single commit is identifiable as the mistake.

**Implications.** The test in §15 is applied and its answers are recorded, not
merely considered in passing. A section of `SPEC.md` that cannot name the
constitutional clause justifying it is a candidate for removal.

**Detection.** Process-level and active today. A merged feature with no recorded
§15 answers violates this invariant even when the feature itself is sound,
because the absence of the record is what permits the next one.

### Invariant 11 — One consistent state per query

**Statement.** A query is answered against one consistent state of the graph. A consumer never observes a partially updated graph.

**Rationale.** Without this, every consumer must defensively handle a graph that
disagrees with itself, and that defensive handling leaks into every public
contract. Once consumers have built around an inconsistent graph, the guarantee
can never be introduced later without breaking them — it is the clearest case
of a property that must exist from the first version or never.

**Implications.** Readers and writers are separated by a versioning mechanism.
No public surface returns a result assembled from more than one state. "The
index is rebuilding" is never part of a correctness explanation given to a
consumer.

**Detection.** Query a fixture repository concurrently with a reindex. Every
result must be identical to the result taken strictly before or strictly after
the reindex. A mixture of the two is a violation.

### Invariant 12 — Accuracy is measured, not claimed

**Statement.** The accuracy of the graph must be measurable. Any claim that `semidx` provides exact program relationships must be backed by a reproducible measurement against known fixtures, per language and per relationship kind.

**Rationale.** *Exact* is the product claim in §16. An unmeasured claim degrades
silently, and it degrades fastest precisely when language coverage widens, which
is also when it is most tempting to stop checking.

**Implications.** Fixture repositories with ground-truth relationships are a
deliverable, not an internal detail of a test suite. Measurements are per
language and per relationship kind, and they are published alongside the
capability matrix rather than kept internal.

**Detection.** Self-detecting and active today: the absence of a current
measurement is itself the violation. No implementation is required to observe
it.

### Invariant 13 — Degradation is reported

**Statement.** Degradation is a reported property of the system, not an internal detail. Identity breaks, unresolved assertions, and relationship kinds a frontend cannot produce must be observable by consumers rather than hidden behind a uniform-looking graph.

**Rationale.** A graph that looks uniform while being partial teaches consumers
to trust it uniformly. The harm then lands at the consumer, is invisible where
it is caused, and surfaces as inexplicably wrong answers far from the frontend
that could not resolve anything. Honest partial coverage is usable; undisclosed
partial coverage is worse than no coverage.

**Implications.** Coverage and resolution information is part of the response
contract, not diagnostic output that may be dropped. "Nothing found" must be
distinguishable from "not supported here" on every public surface.

**Detection.** For each public surface, query a construct that is knowingly
unsupported. The response must distinguish absence from incapacity. A surface
that returns an empty result for both is a violation.

---

## 13. Explicit Non-Goals

`semidx` is not primarily:

* a code chatbot;
* a generic RAG framework;
* a vector database;
* a repository-wide grep replacement;
* an IDE;
* a compiler;
* a documentation generator.

It may support these systems.

It must never become them.

---

## 14. Long-Term Direction

The intended evolution is:

```text
Phase 1
Structural semantic index
        ↓
Phase 2
Exact semantic dependency graph
        ↓
Phase 3
Incrementally maintained graph
        ↓
Phase 4
Fine-grained change and impact analysis
        ↓
Phase 5
Compiler-grade dependency/invalidation capabilities
```

AI retrieval, MCP, vector search, documentation linkage, and IDE integration may evolve alongside these phases but must remain consumers of the same semantic foundation.

---

## 15. Architectural Decision Test

Before introducing a major feature or dependency, ask:

1. What semantic entity or relationship does this add?
2. Does it improve the source-of-truth graph or merely provide another view over it?
3. Does it preserve stable semantic identity?
4. Does it preserve incremental update capability?
5. Does it keep facts, partially resolved assertions, and approximate assertions separate?
6. Could this decision cause the product to drift toward RAG, grep, or vector search as the center?
7. Does it make future dependency and impact analysis easier or harder?
8. Does every assertion it introduces carry its source and resolution level?
9. Does it depend on an unresolved open question in §17?

A "yes" to question 9 blocks the change until that question is closed in §17. An open question must never be settled implicitly by the first implementation that happens to need an answer.

A change that violates an invariant must not be merged. There is no procedure for relaxing an invariant to accommodate it — see §18.

---

## 16. Definition of semidx

The canonical one-sentence definition of the project is:

> **semidx is an incrementally maintained semantic graph of a codebase that provides exact program relationships as a foundation for search, AI context, navigation, impact analysis, and future incremental analysis and compilation tooling.**

All architectural decisions must remain compatible with this definition.

---

## 17. Open Constitutional Questions

These are decisions of constitutional weight that are not yet made. They are
recorded here rather than hidden inside hedged wording, because an unresolved
question that is visible can be decided deliberately, while one buried in a
qualifier gets decided by whichever implementation reaches it first.

Every open question must be closed before this document is ratified — an open
question is the one thing that keeps it in draft. Implementation work that
depends on an answer is blocked until the question is closed (§15, question 9).

After ratification this section must be empty, because a frozen document cannot
answer a question later.

### OQ-2 — Deployment shape

* **Option A.** Local-first. `semidx` must remain fully operable as a local
  process with no required external service.
* **Option B.** Service-oriented. A shared instance serving multiple consumers
  may be a required deployment mode.

Why this is constitutional: it decides whether an external database or service
dependency is permissible at all, which in turn constrains the storage model,
the process model, and the memory and startup budgets in `SPEC.md`. It also
changes what the product is from a consumer's perspective.

Must be resolved before the storage and process model are chosen.

---

## 18. Ratification And Immutability

### Draft

While the status line at the top of this document reads DRAFT, the document is
being written. Text may change freely, and §17 must be emptied.

Ratification is the act of setting that status line to RATIFIED with a date. It
requires §17 to be empty: an unresolved constitutional question is the one thing
that keeps the document in draft, because a frozen document cannot answer a
question later.

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
its own constitution, and let the two projects be what they each are. That is
deliberately expensive, because the alternative — editing the definition of the
product to match what was built — is the failure this document exists to
prevent, and it is cheap enough to happen by accident.

Two consequences follow, and both are intended:

* **Getting it right before ratification matters more than getting it written.**
  A frozen constraint that is wrong cannot be fixed in place. Review before
  ratification is the only review there is.
* **The pressure to reinterpret must be refused, not accommodated.** When a
  clause becomes inconvenient, the temptation is to reread it rather than to
  fork — and silent reinterpretation is worse than an edit, because it leaves no
  trace. A clause that cannot be followed as written is grounds for a fork, not
  for a generous reading.

No log of changes is kept here, because there are no changes to log. The
drafting history lives in `git log`, and durable technical decisions belong in
ADRs.

