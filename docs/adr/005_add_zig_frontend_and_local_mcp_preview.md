---
title: "Add Zig frontend and local MCP preview"
doc_type: "adr"
lifecycle: "accepted"
status: "accepted"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# 005: Add Zig Frontend And Local MCP Preview

## Feature Or Dependency

`semidx` is implemented in Zig, but the current graph cannot index Zig source.
The repository also has no public or local consumer surface: `semidx-dev` is a
developer inspection command, and there is no MCP, HTTP, schema, persistence, or
runtime mirror.

This decision admits two coordinated additions:

- a Zig language frontend, so the rebuilt implementation can index its own
  source tree; and
- a local MCP preview, so local AI clients can query the graph without making
  MCP the semantic model.

The implementation plan is
[004: Zig Frontend And MCP Preview](../plans/004_zig_frontend_and_mcp_preview.md).

## Decision

The Zig frontend will enter through the existing tree-sitter adapter and local
grammar-source mechanism from
[ADR 002](002_local_tree_sitter_parser_dependency.md). The first Zig coverage is
deliberately narrow: named top-level declarations and same-unit simple calls
whose target is a current Zig definition in the same source unit. Unsupported
constructs, unresolved designators, parse failures, and unavailable grammar
analysis remain distinct diagnostics or assertions.

The implementation may add `zig` to source language discovery and may add a
pinned local `tree-sitter-zig` grammar checkout to
`scripts/setup-tree-sitter-grammars.sh`. Builds and indexing still use only
local files. No build or index path may fetch the grammar or runtime from the
network.

The MCP server will be a local stdio preview over the graph's published
snapshot. It is a consumer and projection, not a producer of semantic claims.
It may expose graph query tools such as repository map, definition lookup,
references, context, refresh, and health/capabilities. Those tools must return
graph-first structured data: entity ids, source-unit ids, paths, ranges,
semantic kinds, relationships, resolution, freshness, producer, diagnostics, and
snapshot revision. They must not reinterpret unresolved or approximate
assertions as facts.

The preview supports stdio transport first. The server must write only valid
MCP JSON-RPC messages to stdout and may log to stderr. To make the first local
preview useful across clients, it may support both:

- the `2025-06-18` initialization lifecycle (`initialize`,
  `notifications/initialized`, `tools/list`, `tools/call`); and
- the current stateless discovery path (`server/discover` with per-request
  `_meta`) described by the `2026-07-28` MCP documentation.

If the two protocol shapes conflict in implementation, the stage stops and
records the selected compatibility target before merging code.

Source text, embedded resources, and rendered snippets are disabled by default.
The first preview should return locations and graph context; direct source-text
content requires an explicit command-line opt-in naming the allowed data shape,
for example a flag that enables bounded snippets for the configured local root.
Remote transports are out of scope.

The MCP preview does not publish a semantic contract version. Its tool schemas
are an experimental consumer interface around the current implementation. When
`SPEC.md` later publishes a semantic contract version, MCP results must report
the contract version they use.

## Rationale

Zig onboarding is the shortest route to dogfooding: agents working on this
repository need to answer "what exists here?" and "what refers to what?" about
the implementation itself. A narrow Zig frontend provides real value without
pretending to model Zig's full import, comptime, namespace, container, generic,
or method-call semantics.

Using tree-sitter keeps parsing inside the existing dependency boundary: one C
ABI adapter, local grammar sources, and no parser dependency in `src/core/`.
Using a pinned grammar commit rather than a moving branch keeps builds
repeatable.

MCP is useful because local AI clients can discover and call graph-backed tools.
It must remain on the consumer side of the architecture: the protocol can shape
tool names and result envelopes, but it cannot decide what the graph means or
which assertions are facts. That boundary is constitutional.

Default-off source text keeps local operation honest. The server can still be
useful by telling the client which semantic entities, relationships, paths, and
ranges matter; a client that already has filesystem access can read files
through its own approved local tools.

## Constitutional Decision Test

1. **Semantic graph as source of truth.** Preserved. Zig frontend assertions
   enter through normal reconciliation, and MCP only queries snapshots.
2. **Nodes as entities, not chunks.** Preserved. Zig definitions and source
   units are entities; MCP context may include ranges but does not create chunk
   nodes.
3. **Facts, unresolved, and approximate stay distinct.** Preserved. The Zig
   frontend records facts only for covered exact cases. MCP returns resolution
   and freshness metadata rather than flattening assertion categories.
4. **Stable semantic identity.** Preserved. Zig identities use normal graph
   evidence and correspondence, not tree-sitter node ids, ranges, or MCP result
   ids.
5. **Incrementality and consistent observation.** Preserved. Zig analysis uses
   existing source-unit update paths. MCP queries a published snapshot and
   refreshes by applying scan/edit operations before publishing a new snapshot.
6. **Language frontends preserve meaning.** Preserved. Zig-specific constructs
   stay in Zig extension vocabulary; no new core kind is admitted by this
   decision.
7. **Consumers do not define the model.** Preserved. MCP tools are projections
   over graph queries and do not establish program relationships.
8. **Local operation without mandatory source-data transmission.** Preserved.
   The first server is local stdio, does not require external services, and
   disables source-text transfer by default.

## Consequences

- `semidx` can index a useful slice of its own Zig source before full language
  coverage exists.
- The build and setup scripts gain one more local grammar prerequisite for the
  full lane. `zig build test-core` must continue to work when grammar sources
  are absent.
- MCP introduces an experimental consumer surface. It must be documented as a
  preview and verified through protocol smoke tests, but it is not a published
  semantic contract.
- The first MCP server rebuilds or refreshes an in-memory graph; persistence,
  file watching, HTTP, resources, prompts, pagination beyond small bounded
  lists, and outbound remote integrations remain future work.
- Returning source text through MCP needs an explicit opt-in and separate tests
  proving the default does not leak source-derived content.

## Verification Evidence And Planned Checks

Plan 004 must add tests proving:

- `.zig` files are discovered and routed to the Zig frontend;
- missing grammar sources still leave `zig build test-core` green;
- covered Zig definitions and same-unit simple calls become current facts;
- unsupported Zig constructs do not become approximate facts;
- edits preserve identity where existing correspondence rules establish it;
- MCP stdio handles initialization/discovery, `tools/list`, and `tools/call`
  without stdout pollution; and
- MCP tool output preserves resolution, freshness, producer, diagnostics, and
  the default no-source-text rule.
