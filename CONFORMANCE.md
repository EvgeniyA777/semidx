---
title: "Conformance requirements"
doc_type: "specification"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-13"
---

# semidx Conformance

This document turns [ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md)
into reviewable and eventually executable checks. It is not immutable. Better
checks may replace weaker checks when they verify the same constitutional
property more directly.

There is no executable conformance suite. Every scenario below is a requirement
for future verification, not a claim of passing behavior. The first
implementation slice provides evidence for some of them; see Current Status.

## Conformance Principles

Conformance checks must prove semantic properties, not one current mechanism.

For example, a check may require that an implementation-only edit does not
invalidate interface dependents. It must not require the word "fingerprint" if a
future revision, epoch, dependency-generation, or transactional model proves the
same property.

Checks should remain:

* reproducible from source, configuration, dependencies, producer versions, and
  semantic contract versions;
* explicit about whether they compare ordered results, unordered results, graph
  facts, unresolved assertions, approximate assertions, or operational metadata;
* tied to a constitutional clause and to a requirements document that adopts the
  check.

## Required Scenario Families

| Constitutional property | Required scenario |
| --- | --- |
| Graph authority | Trace semantic answers from public surfaces back to graph facts or attributed assertions. Candidate discovery, ranking, and rendering may use text or projections, but program relationships must come from the graph. |
| Entity nodes | Reflow whitespace, move declarations, and change retrieval window boundaries; node identity must remain tied to entities or source containers, not byte ranges or splitting rules. |
| Knowledge categories | Attempt to record assertions without source or resolution; construction must reject them. Fixtures with unresolved and approximate evidence must expose non-zero counts without promoting them to facts. |
| Stable identity | Repeat fixed-input builds and replay edit histories containing body edits, moves, renames, and permitted loss cases; compare semantic identities and recorded identity breaks. |
| Incremental maintenance | Apply local edits with known affected regions and transitive dependents; unrelated repository growth must not force whole-repository semantic work unless the edit has repository-wide semantic effects. |
| Consistent observation | Query while reindexing or updating; every semantic result must correspond to one complete published graph state, with deterministic order where order is part of the contract. |
| Core and extensions | Compare frontends against the same core definition; coverage may differ, but core meaning may not. Language-specific assertions must retain their own vocabulary instead of being flattened into core approximations. |
| Honest degradation | Query constructs with confirmed absence, unsupported language constructs, unavailable analysis, unresolved targets, and approximate evidence; each must be distinguishable from the others on every public surface. |
| Optional vectors | Build and query graph answers with embeddings disabled. Candidate discovery from natural-language intent may differ, but graph answers at fixed entity, snapshot, filters, and traversal parameters must not. |
| Local operation and privacy | From a clean checkout with no service reachable, build and query the graph. With default settings and network available, observe that no source code or source-derived data leaves the machine during indexing, querying, or optional projections. |
| Consumer independence | Remove or disable one public interface such as MCP; no concept, entity kind, or relationship kind may leave the model with it, and the remaining model must still express the same semantic questions. Schema concepts must not depend on one consumer protocol's vocabulary. |
| Accuracy claims | Any published claim of exact relationships must have current reproducible evidence against known fixtures, per language and per relationship kind. Planned behavior must be labeled as unmeasured. |

## Source Of Expected Results

Expected results for semantic fixtures belong with the requirements that adopt
them. They should identify:

* source repository or fixture revision;
* analysis configuration and dependency inputs;
* producer versions and semantic contract version;
* expected entities, relationships, identity correspondences, resolution levels,
  and approximate outputs where applicable;
* ordered-result tie rules where order is observable;
* known limitations from the capability matrix.

The capability matrix must distinguish confirmed absence, unsupported language
constructs, unavailable analysis, runtime analysis failures, unresolved claims,
and approximate evidence.

## Publication Gates

Before a semantic contract, frontend, public surface, or accuracy claim is
published, the adopting requirements must identify which scenario families are
applicable and which evidence satisfies them.

A release may deliberately publish partial coverage only when that partiality is
visible to consumers. "Nothing found" and "not supported here" must not share
the same public result shape.

## Current Status

No scenario family above is adopted as an executable gate, and no schema or
public surface exists to check one against.

The first implementation slice
([plan](docs/plans/001_zig_vertical_slice.md),
[evidence](docs/reports/001_zig_vertical_slice_progress.md)) produces evidence
for the five properties this section asked of it:

* **entity nodes rather than chunks** — ids are allocated by the graph and never
  derived from a range; definitions sharing a range stay distinct entities, and
  moving a definition changes only its projection;
* **facts versus unresolved assertions** — construction rejects an unresolved
  target presented as a fact and a resolved target claiming its target is
  missing; the fixtures carry unresolved targets in both languages and none of
  them is a fact;
* **identity across a simple edit** — a body edit preserves every entity id, and
  a rename is recorded as identity loss naming its replacement rather than as an
  unrelated deletion and creation;
* **one incremental update against one consistent observable state** — a
  snapshot published before an edit keeps observing that state while only the
  changed source unit is reanalyzed;
* **local indexing and querying with no external service** — the build declares
  no dependencies, reads only local paths, and the slice indexes and queries
  with nothing else running.

That evidence is fixture-scoped. It is not a capability matrix, not a
per-language accuracy claim, and not a substitute for adopting these families as
gates.
