# semidx — Architecture Constitution

**Constitution version: 5.** Amendment history is recorded in §19.

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

This document is versioned rather than lifecycled: it has no `status` or
`lifecycle` state, because it is never superseded by a newer current document —
it is amended in place under §18.

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
question, that question is recorded in §17 instead. Reintroducing one is a
weakening amendment under §18 and requires a §19 entry.

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

Frontends translate language-specific information into the common semantic model.

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
process rather than of code. The amendment procedure in §18 is already enforced
mechanically by `scripts/check-constitution-amendment.sh`.

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

### Invariant 8 — Frontends feed a shared model

**Statement.** Language-specific analysis must feed a shared semantic model rather than define its own private one.

How far that model is unified across languages is an open question (OQ-1, §17). Until OQ-1 is resolved, "where practical" is a tracked decision, not a discretionary exemption an implementation may grant itself.

**Rationale.** A frontend that writes its own private model makes cross-language
questions impossible and makes its own output unreviewable, because there is no
common definition to check it against. Coverage differences between languages
are legitimate; private vocabularies are not.

**Implications.** No frontend writes to storage in its own vocabulary.
Translation happens at a named boundary (§10). Until OQ-1 is resolved, no
schema commitment may be made that presupposes either answer.

**Detection.** Frontends must be replaceable. Swapping one frontend for another
covering the same language must change resolution levels and coverage, never the
shape of the graph. If it changes the shape, the frontend was defining the
model.

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

A "yes" to question 9 blocks the change until that question is resolved by amendment. An open question must never be settled implicitly by the first implementation that happens to need an answer.

If a change violates the architectural invariants, it must not be merged without amending this document first, under the procedure in §18.

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

An open question is resolved only by amendment under §18. Implementation work
that depends on the answer is blocked until then (§15, question 9).

### OQ-1 — Degree of cross-language model unification

Referenced by Invariant 8.

* **Option A.** One shared vocabulary of entity and relationship kinds. Every
  language frontend maps onto it. Consumers get uniform queries across
  languages; language-specific constructs are either flattened or lost.
* **Option B.** Per-language semantic schemas with a shared query layer above
  them. Language-specific constructs survive intact; uniform cross-language
  questions require an explicit translation layer.

Why this is constitutional: the answer determines what happens to constructs
that do not unify cleanly — multimethods and protocols, behaviours and dynamic
dispatch, generics and ABI, structural typing. Reversing the choice after a
schema is in use is a rewrite, and the schema is the consumer-visible contract.

Must be resolved before the assertion schema is committed to in `SPEC.md`.

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

## 18. Amendment Procedure

* This document changes only by explicit amendment.
* An amendment is a standalone commit. It must not be combined with the code or
  documentation change that it permits.
* Every amendment increments the constitution version and adds an entry to §19.
* Weakening a constraint is an amendment, not a clarification. Replacing `must`
  with `may`, adding an exemption, and widening an existing exemption all
  require a §19 entry stating what is now permitted that was not before.
* Resolving an entry in §17 is an amendment.
* Moving a constraint from this document to `SPEC.md` is an amendment, because
  it makes that constraint subject to drift.

---

## 19. Amendment Log

| Version | Date | Change | Rationale |
| --- | --- | --- | --- |
| 5 | 2026-09-12 | Renamed the Terminology section to Defined Terms and cut it from twelve entries to five: entity, node, relationship, assertion, fact. Moved `frontend`, `snapshot`, `fingerprint`, `consumer`, `projection`, `symbol`, and `edge` to `GLOSSARY.md`, which also now defines `provenance`, `resolution level`, and `capability matrix` — three terms this document had been using without defining anywhere. Dropped the claim that the section binds `SPEC.md` and the implementation. | Version 3 corrected a real defect but overshot: it carried a general glossary into a document whose Scope section forbids exactly that kind of accumulation. Seven of the twelve entries defined nothing that was not already defined in place by the section using them, and two carried nothing normative at all — `symbol` is a convenience subset, and `edge` appeared exactly once in the whole document outside its own definition. The five that remain are different in kind: each states a distinction that an invariant turns on, so removing them would leave obligations written in undefined words. The dropped binding claim was over-reach in the opposite direction — dictating vocabulary to a document that does not exist yet is precisely the sort of thing that must be free to drift. `GLOSSARY.md` was created first so no term was left without an owner between the two commits. |
| 4 | 2026-09-12 | Restated all thirteen invariants in four parts — Statement, Rationale, Implications, Detection — and gave each a short name. No invariant's obligation was changed, weakened, or added; this amendment adds justification, consequences, and a means of observing violation to the existing thirteen. | Two gaps. First, the invariants stated obligations without recording why they exist, so a later reader could see a prohibition but not its purpose — and therefore could not judge whether a proposed exception defeated it. That is the mechanism by which principles erode: not a decision to abandon them, but a sequence of exceptions that each look local. Second, no invariant said how a violation would be detected, which left the whole document on an honour system — the same weakness `RULES.md` already admits about its own Code Reading Rules. Most Detection entries need an implementation that does not exist yet; they are written now so each check derives from its invariant rather than being invented afterwards to match whatever was built. Invariants 10 and 12 are detectable today because they are properties of the process, and §18 is now enforced mechanically by `scripts/check-constitution-amendment.sh`. |
| 3 | 2026-09-12 | Added the Normative Language section (RFC 2119 keywords, `SHOULD` declared unused, discretionary qualifiers banned from normative statements) and the Terminology section. Unified vocabulary across the document: entity vs node, relationship vs edge, and — the substantive one — **assertion** vs **fact**, where a fact is now defined as a fully resolved, frontend-confirmed assertion rather than a synonym. Replaced every remaining `should` with `must` or `must never` (§5, §8, §9, §13, §16). Retermed §3's graph diagram, §4 L1 and L2, §10, §11, Invariants 2 and 3, §15 question 5, and OQ-1. | Two gaps measured against standard practice. First, the version 2 amendment turned on the difference between `must` and `may` without the document ever declaring that those words were normative rather than stylistic, and four `should`s survived in normative positions. Second, the document mixed entity/node/symbol, relationship/edge, and fact/assertion as synonyms — and the version 2 amendment made that worse by introducing `assertion` and `edge` alongside the existing `fact` and `relationship`. For a document whose subject is exactness, and which is read by agents, that is a defect rather than a style question: `fact` and `assertion` differ precisely where §11 draws its line, so using them interchangeably asserts resolution that may not exist. Fixed before `SPEC.md` is written, so the assertion schema does not inherit the ambiguity. |
| 2 | 2026-09-12 | Added the document's own scope boundary and the constitutional-versus-`SPEC.md` test. Hardened §5 (stable identity is unconditional, with a closed exemption list) and §7 (aspect-separated fingerprints are required, not optional). Extended §11 with partially resolved assertions and the Provenance Rule, and applied it to identity claims in §5. Fixed two observable properties of incrementality in §6. Amended Invariants 3 and 8; added Invariants 11, 12, 13. Added questions 8 and 9 to §15. Added §17, §18, §19. | The document defended strongly against becoming a RAG, grep, or vector-search product, but its positive requirements — the expensive, hard-to-reproduce ones — were written with `may`, `where useful`, and `where practical`. Drift was unlikely to arrive as a proposal to build a vector database; it was likely to arrive as a hundred local "not practical here" decisions, each individually defensible. This amendment converts those qualifiers into obligations with named exemptions, makes the two genuinely undecided forks visible as tracked questions instead of qualifiers, and gives the document an amendment record so it cannot be edited into agreement with the code it is supposed to constrain. |
| 1 | 2026-09-12 | Initial document. | Fix the architectural target before any implementation exists, so a from-scratch rebuild has something to conform to. |
