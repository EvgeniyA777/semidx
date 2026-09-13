---
title: "Architecture rationale"
doc_type: "rationale"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-13"
---

# semidx Architecture Rationale

This document explains why the constitution says what it says. It is not
ratified, immutable, or independently normative. If this file and
[ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md) conflict, the
constitution wins.

## Why A Constitution Exists

`semidx` is easy to erode because the useful adjacent products are easier to
build than the product itself. A RAG pipeline, a lexical index, an MCP wrapper,
or a code chatbot can all ship useful value before a maintained semantic graph
exists. If one becomes the center, the graph stops being the source of truth and
turns into optional weight.

The constitution protects only the identity boundary: the parts that make the
project `semidx` rather than a more convenient code-search system.

The earlier draft mixed that boundary with engineering policy and conformance
mechanics. Those details are still useful, but freezing them would make one
badly chosen test fixture, fingerprint mechanism, or publication procedure as
hard to change as the product identity itself.

## The Irreducible Core

The distilled architecture is:

```text
source
  ↓
language analysis
  ↓
semantic entities
  ↓
exact relationships
  ↓
persistent semantic graph
  ↓
incremental maintenance
  ↓
consumers
```

The non-negotiable properties are:

* stable semantic identity;
* provenance and resolution;
* incrementality with consistent observation;
* exact knowledge kept separate from unresolved and approximate knowledge;
* language-specific meaning preserved while contributing to a common core;
* consumers that read the model rather than define it;
* local operation without mandatory external infrastructure or source-data
  transmission.

Removing any one of these changes the product. Changing a mechanism that
implements one of them usually does not.

## Why Nodes Are Not Chunks

Chunks are retrieval artifacts. They are defined by text boundaries and are
useful for search, display, and embedding windows. They cannot carry stable
semantic identity, cannot be reliable endpoints of exact relationships, and
cannot support fine-grained invalidation.

Entities are source organization or program meaning. Their text locations can
change while the modeled thing remains the same. That is the difference that
makes incremental semantic history possible.

## Why Exactness Is A Product Claim

Exact does not mean complete. It means the system does not present an assertion
as a fact unless it has been established.

This distinction lets `semidx` remain useful for dynamic or incomplete
languages. A frontend may know that a call-like reference exists while the
target is unresolved. Dropping that assertion loses useful information.
Promoting it to a fact makes the graph false. Keeping a separate unresolved
category preserves both honesty and usefulness.

Approximate retrieval belongs in projections. It may discover candidates, rank
results, or connect related material, but it must not establish program
relationships.

## Why Identity Is Protected

Identity damage is hard to detect after the fact. A broken identity history
looks like ordinary deletion and creation, and later evidence usually cannot
reconstruct the intended correspondence.

For that reason, identity is constitutional while any particular identity
algorithm is not. The project may use names, syntax, compiler data, fingerprints,
semantic revisions, generations, or other evidence. The protected property is
that established correspondence survives ordinary edits and identity loss is
reported as such.

## Why Incrementality Is Core

Incrementality is not a later performance optimization. Retrofitting it after a
system assumes whole-repository rebuilds usually requires rewriting storage,
identity, invalidation, and public observation semantics together.

The constitution therefore fixes the semantic property: a graph can be updated
from an existing graph after a source change, and consumers observe one
consistent state. It does not freeze MVCC, immutable roots, transaction swaps,
fingerprints, revision counters, dependency generations, or another future
mechanism.

## Why The Core Must Stay Small

The shared core exists so consumers can ask cross-language questions without
forcing every language into one vocabulary. It must be sufficient for common
existence and reference questions, but it must not absorb language-specific
meaning merely because that meaning is important.

Flattening language semantics loses information at write time. A missing
extension mapping loses convenience at read time. The first loss is permanent;
the second can be fixed later.

The core roster is therefore a requirements artifact, not constitutional text.
Published meaning deserves compatibility and migration rules, but candidate
membership must remain correctable before publication.

## Why Consumers Stay Downstream

MCP, RAG, IDEs, agents, search, documentation linkage, impact analysis, and
compilation tooling are all legitimate consumers. Their needs should influence
interfaces and prioritization.

They must not define what the graph means. The model has to outlive any single
protocol, retrieval technique, or product surface.

## Why Local Operation Matters

The graph answers questions about the developer's current working copy,
including uncommitted edits. A mandatory shared service cannot be the authority
for that state. It can provide cache, acceleration, or a reproducible baseline,
but the local process must still be able to build, update, and query the graph.

Source privacy is part of the same boundary. Optional outbound consumers may
exist, but source code and source-derived data leaving the machine must be an
explicit user choice, not a default graph requirement.

## Where The Detailed Work Went

The detailed draft material was not discarded:

* [SPEC.md](SPEC.md) owns changing requirements and semantic contract
  lifecycles.
* [CORE.md](CORE.md) owns core-kind candidates and admission evidence.
* [CONFORMANCE.md](CONFORMANCE.md) owns reviewable and executable checks.
* ADRs under [docs/adr/](docs/adr/) own durable decisions and their historical
  reasoning. None exist yet; the sequence starts at `001`.

This split keeps the constitution strong by making it smaller.
