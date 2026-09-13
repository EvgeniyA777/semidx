# semidx — Architecture Constitution

**Constitution version: 2.** Amendment history is recorded in §19.

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
│ symbols                 │
│ types                   │
│ references              │
│ calls                   │
│ dependencies            │
│ relationships           │
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

Represents structural facts extracted from source code.

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

Represents exact relationships between program entities.

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

Graph nodes must represent semantic entities, not text fragments.

A symbol must retain a stable identity across edits.

Example:

```text
UserService.login
```

should remain conceptually the same graph entity when its body changes.

Changes must be represented as changes to properties or dependencies of that entity rather than blindly deleting and recreating unrelated chunks.

Stable identity is required for meaningful incremental updates.

### Permitted Identity Breaks

Identity may be broken only when:

* the entity was genuinely removed from the program;
* no available frontend fact can distinguish the entity from a sibling — for
  example, two otherwise identical anonymous entities in the same scope;
* the frontend supplies no identity-bearing fact for that class of entity at
  its current capability level.

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

After relevant semantic entities are found, exact graph relationships should answer:

> What calls this function?
> What type does it depend on?
> What will be affected if it changes?

Approximate retrieval discovers candidates.

The semantic graph establishes program relationships.

---

## 9. AI and MCP Are Consumers

AI agents are important consumers of `semidx`, but `semidx` must not be architected specifically as an AI chat backend.

Agents should be able to ask questions such as:

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

Language-specific tools may provide facts to the semantic model.

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

The system must distinguish exact program facts, partially resolved assertions,
and approximate semantic similarity. These are three categories, not two.

Exact:

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

Approximate relationships must never silently become authoritative graph facts.

A partially resolved assertion is exact in kind but unresolved in target. It is
neither an exact program fact nor a similarity judgement, and it must not be
coerced into either.

Coercing it upward — recording an unresolved call as a resolved `CALLS` edge —
makes the graph state falsehoods. That is the one thing the word *exact* in §16
forbids outright.

Discarding it — dropping every unresolved assertion — empties the graph exactly
in the languages where dynamic dispatch dominates, which makes the system
useless where it is needed most.

Both failures are avoided by the same rule.

### Provenance Rule

Every assertion in the graph — that a relationship exists, what its target is,
that two entities across snapshots are the same entity — must carry:

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

### Invariant 1

The semantic graph is the architectural center.

### Invariant 2

Graph nodes represent semantic program entities, not arbitrary chunks of text.

### Invariant 3

Exact dependencies, partially resolved assertions, and approximate similarity are three separate concepts, and every assertion carries its source and resolution level (§11).

### Invariant 4

Vector search is optional. The semantic graph is not.

### Invariant 5

RAG is a consumer of `semidx`, not the definition of `semidx`.

### Invariant 6

MCP is an interface, not the core.

### Invariant 7

The architecture must preserve a path toward incremental graph maintenance.

### Invariant 8

Language-specific analysis must feed a shared semantic model rather than define its own private one.

How far that model is unified across languages is an open question (OQ-1, §17). Until OQ-1 is resolved, "where practical" is a tracked decision, not a discretionary exemption an implementation may grant itself.

### Invariant 9

Architectural shortcuts must not destroy stable semantic identity.

### Invariant 10

A feature that does not strengthen the semantic model or consume it must justify why it belongs in `semidx`.

### Invariant 11

A query is answered against one consistent state of the graph. A consumer never observes a partially updated graph.

### Invariant 12

The accuracy of the graph must be measurable. Any claim that `semidx` provides exact program relationships must be backed by a reproducible measurement against known fixtures, per language and per relationship kind.

### Invariant 13

Degradation is a reported property of the system, not an internal detail. Identity breaks, unresolved assertions, and relationship kinds a frontend cannot produce must be observable by consumers rather than hidden behind a uniform-looking graph.

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

It should not become them.

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
5. Does it keep exact facts separate from approximate retrieval?
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

All architectural decisions should remain compatible with this definition.

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

* **Option A.** One shared vocabulary of node and relationship kinds. Every
  language frontend maps onto it. Consumers get uniform queries across
  languages; language-specific constructs are either flattened or lost.
* **Option B.** Per-language semantic schemas with a shared query layer above
  them. Language-specific constructs survive intact; uniform cross-language
  questions require an explicit translation layer.

Why this is constitutional: the answer determines what happens to constructs
that do not unify cleanly — multimethods and protocols, behaviours and dynamic
dispatch, generics and ABI, structural typing. Reversing the choice after a
schema is in use is a rewrite, and the schema is the consumer-visible contract.

Must be resolved before the fact schema is committed to in `SPEC.md`.

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
| 2 | 2026-09-12 | Added the document's own scope boundary and the constitutional-versus-`SPEC.md` test. Hardened §5 (stable identity is unconditional, with a closed exemption list) and §7 (aspect-separated fingerprints are required, not optional). Extended §11 with partially resolved assertions and the Provenance Rule, and applied it to identity claims in §5. Fixed two observable properties of incrementality in §6. Amended Invariants 3 and 8; added Invariants 11, 12, 13. Added questions 8 and 9 to §15. Added §17, §18, §19. | The document defended strongly against becoming a RAG, grep, or vector-search product, but its positive requirements — the expensive, hard-to-reproduce ones — were written with `may`, `where useful`, and `where practical`. Drift was unlikely to arrive as a proposal to build a vector database; it was likely to arrive as a hundred local "not practical here" decisions, each individually defensible. This amendment converts those qualifiers into obligations with named exemptions, makes the two genuinely undecided forks visible as tracked questions instead of qualifiers, and gives the document an amendment record so it cannot be edited into agreement with the code it is supposed to constrain. |
| 1 | 2026-09-12 | Initial document. | Fix the architectural target before any implementation exists, so a from-scratch rebuild has something to conform to. |
