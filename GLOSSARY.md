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
constraints — Invariant 2 turns on entity versus chunk, and §11 turns on
assertion versus fact. Repeating them here would give them two owners. Look
them up there.

## Terms

**capability matrix** — The published statement of what `semidx` can and cannot
analyze, per language, producer version, and entity or relationship kind,
including identity limitations of frontends and source ingestion. It exists
because accuracy must be measurable (Invariant 12) and degradation visible to consumers rather
than hidden behind a uniform-looking graph (Invariant 13).

**consumer** — Anything that reads the graph rather than producing it: search,
AI agents, IDE integration, impact analysis. The direction is the point —
consumers depend on the graph, never the reverse (constitution §1, §3,
Invariant 1).

**edge** — The graph's representation of a relationship. Use it only where the
representation itself is the subject; the relationship is the thing being
modelled, the edge is how it is stored.

**fingerprint** — A digest of one aspect of an entity's meaning — its signature,
its type, its implementation, its dependencies. Used to decide what a change
invalidates. Fingerprints are aspect-separated by requirement, not by
convenience (constitution §7).

**frontend** — A language-specific component that produces assertions about
source code for the model: a parser, a Tree-sitter grammar, a SCIP indexer, a
compiler API, a language server, a static analyzer (constitution §10). Frontends
differ in coverage and in how much they resolve. They do not differ in the model
they feed (Invariant 8).

**projection** — A derived view over the graph that is not a source of truth: a
lexical index, a vector index, a rendered subgraph. A projection can be rebuilt
or discarded without loss (constitution §2, §8).

**provenance** — The record of what produced an assertion: which frontend,
analyzer, or method. Carried by every assertion, alongside its resolution level
(constitution §11, Provenance Rule).

**resolution level** — How far an assertion's semantic claim was established.
The categories and their distinction are owned by constitution §11. The
enumerated values and their encoding are schema requirements owned by
[SPEC.md](SPEC.md).

**snapshot** — One consistent state of the graph: the state a query is answered
against. A consumer never observes a graph assembled from more than one snapshot
(constitution §6, Invariant 11).

**symbol** — A named entity, one a frontend can address by a stable name. A
subset of entities: anonymous constructs are entities but not symbols.

## Document Ownership

The [documentation policy](docs/agent-policy/documentation.md#canonical-ownership)
maps the constitutional document roles to their current files. The core roster
is in [CORE.md](CORE.md); requirements and schema vocabulary are in
[SPEC.md](SPEC.md). Conceptual vocabulary stays here.
