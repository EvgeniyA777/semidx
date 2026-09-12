# semidx — Architecture Constitution

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

A symbol must retain a stable identity whenever possible across edits.

Example:

```text
UserService.login
```

should remain conceptually the same graph entity when its body changes.

Changes must be represented as changes to properties or dependencies of that entity rather than blindly deleting and recreating unrelated chunks.

Stable identity is required for meaningful incremental updates.

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

---

## 7. Change Awareness

Where useful, semantic entities may maintain independent fingerprints for different aspects of their meaning.

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

## 11. Exact and Approximate Knowledge Must Remain Separate

The system must distinguish between exact program facts and approximate semantic similarity.

Exact:

```text
A CALLS B
A USES_TYPE C
D IMPLEMENTS E
```

Approximate:

```text
A is semantically similar to B
this documentation appears relevant to C
these two code regions have similar meaning
```

Approximate relationships must never silently become authoritative graph facts.

This distinction is mandatory.

---

## 12. Architectural Invariants

The following rules must remain true throughout development.

### Invariant 1

The semantic graph is the architectural center.

### Invariant 2

Graph nodes represent semantic program entities, not arbitrary chunks of text.

### Invariant 3

Exact dependencies and approximate similarity are separate concepts.

### Invariant 4

Vector search is optional. The semantic graph is not.

### Invariant 5

RAG is a consumer of `semidx`, not the definition of `semidx`.

### Invariant 6

MCP is an interface, not the core.

### Invariant 7

The architecture must preserve a path toward incremental graph maintenance.

### Invariant 8

Language-specific analysis must feed a language-independent semantic model where practical.

### Invariant 9

Architectural shortcuts must not destroy stable semantic identity.

### Invariant 10

A feature that does not strengthen the semantic model or consume it must justify why it belongs in `semidx`.

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

If a change violates the architectural invariants, it must not be merged without explicitly changing this document first.

---

## 16. Definition of semidx

The canonical one-sentence definition of the project is:

> **semidx is an incrementally maintained semantic graph of a codebase that provides exact program relationships as a foundation for search, AI context, navigation, impact analysis, and future incremental analysis and compilation tooling.**

All architectural decisions should remain compatible with this definition.
