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

**capability matrix** — The published statement of what `semidx` can and cannot
analyze, per language, producer version, and entity or relationship kind,
including identity limitations of frontends and source ingestion. It exists so
partial coverage is visible to consumers rather than hidden behind a
uniform-looking graph.

**consumer** — Anything that reads the graph rather than producing it: search,
AI agents, IDE integration, impact analysis, documentation linkage, or future
compilation tooling. The direction is the point: consumers depend on the graph,
never the reverse.

**edge** — The graph's representation of a relationship. Use it only where the
representation itself is the subject; the relationship is the thing being
modeled, the edge is how it is stored.

**fingerprint** — One possible mechanism for recognizing that some aspect of an
entity's meaning changed. A future design may use semantic revisions,
dependency generations, change epochs, or another mechanism instead. The
requirement is the semantic ability to distinguish changes that matter
differently, not this word.

**frontend** — A language-specific component that produces assertions about
source code for the model: a parser, a Tree-sitter grammar, a SCIP indexer, a
compiler API, a language server, a static analyzer, or a custom extractor.
Frontends differ in coverage and in how much they resolve. They do not define
the model they feed.

**projection** — A derived view over the graph that is not a source of truth: a
lexical index, a vector index, an embedding window, a rendered snippet, or a
rendered subgraph. A projection can be rebuilt or discarded without losing graph
meaning.

**provenance** — The record of what produced an assertion: source ingestion, a
frontend, an analyzer, exact system resolution, or another recorded method.

**resolution level** — How far an assertion's semantic claim was established.
The categories are constitutionally distinct; the concrete enumerated values and
their encoding are schema requirements owned by [SPEC.md](SPEC.md).

**snapshot** — One consistent state of the graph: the state a query is answered
against. A consumer never observes a graph assembled from more than one
snapshot.

**symbol** — A named entity, one a frontend can address by a stable name. A
symbol is a subset of entities: anonymous constructs are entities but not
symbols.

## Document Ownership

The [documentation policy](docs/agent-policy/documentation.md#canonical-ownership)
maps the constitutional document roles to their current files. The rationale is
in [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md); the core roster is in
[CORE.md](CORE.md); requirements and schema vocabulary are in [SPEC.md](SPEC.md);
and conformance scenario families are in [CONFORMANCE.md](CONFORMANCE.md).
Conceptual vocabulary stays here.
