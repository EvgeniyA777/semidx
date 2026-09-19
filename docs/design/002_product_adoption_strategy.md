---
title: "Product adoption strategy"
doc_type: "reference"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-17"
---

# Product Adoption Strategy

This document records the product strategy for making semidx useful enough that
developers install it and local coding agents keep using it after the first
connection. It is not an implementation plan, release plan, or public promise.
Concrete work still moves through plans, ADRs, follow-ups, or explicit tasks.

## Positioning

semidx should be positioned as:

> Local semantic graph for coding agents: exact when it knows, honest when it
> does not.

The project should not compete as a generic code search, chatbot, vector
database, or RAG framework. Its useful difference is a local graph that tells
agents which program entities and relationships are established facts, which
claims are unresolved or stale, and which source regions are unsupported or
unavailable.

## Primary Audience

The first audience is developers already using coding agents on real
repositories.

They feel pain when agents:

- read too many files to orient themselves;
- infer relationships from names or text matches;
- miss impact because call/reference context is scattered;
- repeat cold-start exploration in every session;
- cannot tell whether a source answer is exact, stale, unsupported, or guessed;
- leak source context to remote tools without an explicit decision.

semidx should make that workflow calmer: one local graph-backed tool gives a
bounded orientation and enough provenance for the agent to know what to trust.

## Core Promise

After connecting semidx to a repository, a developer should get a local tool
that helps agents answer:

- what files and top-level definitions exist;
- where a named definition is introduced;
- who references or calls an entity;
- what graph neighborhood matters for a focused edit;
- whether the answer is current, stale, unresolved, unsupported, approximate, or
  unavailable;
- whether the index needs refresh after local edits.

The first promise is not complete language understanding. The first promise is
honest, bounded, local semantic context.

## Agent Habit Loop

Agents will keep using semidx only if it becomes cheaper and safer than manual
file exploration.

The intended habit loop:

1. Start with `semidx_health` to learn whether the graph is current enough.
2. Use `semidx_outline`, then a scoped `semidx_repo_map`, for repository
   orientation instead of broad file reads.
3. Use `semidx_find_definitions` before opening likely definition files.
4. Use `semidx_references` for impact checks before editing.
5. Use `semidx_context` as the default focused-context tool around a symbol,
   path, or entity id.
6. Use `semidx_refresh` after edits instead of assuming the old graph still
   describes the working copy.

The strongest adoption signal is an agent choosing `semidx_context` before
manual grep/read on cold start or impact analysis.

## Product Requirements For Adoption

The preview should optimize for trust and friction before breadth.

Required for early adoption:

- install and local MCP configuration in a few minutes;
- one semidx binary usable against many repository roots via `--root`;
- no source text returned by MCP unless explicitly opted in;
- compact tool schemas and predictable structured results;
- clear resolution, freshness, provenance, diagnostics, and truncation metadata;
- obvious failure modes when parsers, grammars, or analysis are unavailable;
- examples that show the same task before and after semidx;
- a visible capability matrix so users know which languages and relationships
  are actually covered.

Nice later, but not first-preview blockers:

- broad language roster;
- persistence;
- daemon file watching;
- HTTP transport;
- embeddings or ranking;
- IDE-native UI;
- published semantic contract version.

## First Public Proofs

Before asking strangers to care, the project should show concrete workflows:

- connect semidx to this repository and ask for the Zig frontend map;
- find a definition and its calls without broad text search;
- edit a file, refresh, and show the snapshot revision changed;
- ask for context around a target and receive definitions, relationships,
  diagnostics, freshness, and bounded results;
- show unresolved/unsupported cases rather than hiding them.

These proofs should use real project source, not only tiny fixtures.

## Success Metrics

Useful early metrics:

- time from clone to first successful MCP tool call;
- number of manual file reads avoided during agent cold start;
- number of grep-style searches avoided during impact analysis;
- percentage of tool responses that include actionable diagnostics when coverage
  is incomplete;
- latency and output size for repo map, definition lookup, references, and
  focused context;
- count of observed agent sessions where semidx is used before broad manual
  search.

Do not use test count, line count, or language count as product success metrics
by themselves.

## Conversion Into Work

Product strategy becomes implementation work only through smaller artifacts:

- Plan 004 finishes the first local MCP preview.
- Follow-up 004 becomes the release discipline plan for `v0.1.0-preview.1`.
- README gets the public quickstart only after the preview is working.
- A capability matrix belongs in SPEC or a SPEC-owned child document before
  stable claims are made.
- Gaps found through dogfood become follow-up reports or focused frontend plans.
- Stable CLI/MCP behavior for `v0.1.0` gets its own plan and release gate.

## Release Story

Use separate version concepts:

- Product release tags version the semidx binary, CLI, MCP preview, packaging,
  installation docs, and user-facing product behavior.
- Semantic contract versions identify the graph semantics exposed to consumers
  and remain unpublished until SPEC/CORE define that lifecycle.

Recommended product milestones:

- `v0.1.0-preview.1`: local MCP preview usable by the maintainer and local
  agents, with no promise of a stable semantic contract.
- `v0.1.0`: first stable CLI/MCP product release, with documented install path,
  supported commands, version reporting, capability boundaries, and release
  gates.

## Anti-Goals

Do not shape the project around:

- being a generic RAG framework;
- being a chatbot;
- being a vector database;
- being a prettier grep;
- maximizing language count before trust;
- adding remote services as a requirement;
- returning source-derived data without explicit opt-in;
- making MCP tool convenience define graph semantics.

## Strategic Checks

Before major work, ask:

- Does this make agents use less blind context gathering?
- Does this increase exact graph value or make incompleteness clearer?
- Does this keep local operation and source-data control intact?
- Does this improve install, trust, dogfood, or release readiness?
- Can a user understand what is supported without reading the implementation?

If the answer is mostly no, the work is probably not on the adoption path.
