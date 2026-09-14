---
title: "Zig frontend and MCP preview"
doc_type: "plan"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-14"
---

# 004: Zig Frontend And MCP Preview

## Goal

Add enough Zig language support for `semidx` to index its own implementation
source, then expose a local MCP stdio preview that lets local AI clients query
the graph for repository maps, definitions, references, focused context, and
health/capability information.

The governing decision is
[ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md).

## Scope

- Add `zig` as a discovered source language for `.zig` files.
- Add a pinned local `tree-sitter-zig` grammar through the existing ADR 002
  setup/build mechanism.
- Add a Zig frontend with narrow initial coverage:
  - named top-level function declarations;
  - named top-level container/type declarations where the grammar exposes an
    exact declaration name; and
  - same-unit simple call expressions that uniquely target a current covered
    Zig function definition in the same source unit.
- Preserve unsupported, unresolved, failed, unavailable, stale, and approximate
  states as distinct observable outcomes.
- Add a local stdio MCP preview over published snapshots.
- Provide MCP tools for graph-backed repository map, definition lookup,
  references/calls, focused graph context, refresh, and health/capabilities.
- Return graph-first structured results with bounded sizes and explicit
  freshness/resolution/provenance metadata.
- Document local MCP configuration and source-text opt-in behavior.

## Non-Scope

Do not publish a semantic contract version, create `contracts/` schemas, add
persistence, daemon file watching, remote services, HTTP MCP, resources,
prompts, embeddings, vectors, RAG, ranking, IDE integration, generated-source
identity, multi-root identity, or package/module admission.

Do not implement full Zig name resolution, imports, `@import` graph semantics,
namespace/container lookup, comptime evaluation, generics, overload-like
dispatch, receiver typing, method-call resolution, field definitions, local
variable definitions, anonymous tests, build graph modeling, or cross-unit Zig
resolution.

Do not let MCP tool shape change the semantic model. MCP is a projection over
the graph, not an authority for facts.

Do not return source text, embedded resources, or snippets through MCP unless
the server was started with an explicit opt-in flag for that data shape.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  §1, §3, §5, §6, §7, and §8.
- [ADR 001](../adr/001_choose_zig_implementation_language.md) chooses Zig for
  the implementation.
- [ADR 002](../adr/002_local_tree_sitter_parser_dependency.md) owns parser
  dependency shape: local tree-sitter C sources behind one adapter.
- [ADR 003](../adr/003_reject_name_match_assertions.md) forbids repository-wide
  name matching as graph assertions.
- [ADR 005](../adr/005_add_zig_frontend_and_local_mcp_preview.md) admits the Zig
  frontend and local MCP preview.
- [SPEC.md](../../SPEC.md) owns requirements, public contract lifecycle,
  capability matrices, optional outbound data, and future publication.
- [CORE.md](../../CORE.md) owns the current unversioned core roster:
  `repository`, `file`, `definition`, `CONTAINS`, `DEFINES`, `REFERENCES`, and
  `CALLS`.
- [CONFORMANCE.md](../../CONFORMANCE.md) owns scenario families for graph
  authority, knowledge categories, incrementality, frontend/core boundaries,
  degradation, and local operation.
- [MEMORY.md](../../MEMORY.md) owns current implementation reality and known
  gaps.
- Official MCP documentation:
  - <https://modelcontextprotocol.io/specification/2025-06-18>
  - <https://modelcontextprotocol.io/specification/2026-07-28>

## Current Implementation Context

- `build.zig` has parser-dependent full tests and a parser-free `test-core`
  lane. Full builds compile local C parser sources for Java and Clojure.
- `scripts/setup-tree-sitter-grammars.sh` fetches grammar sources into a local
  `.tree-sitter-grammars` directory; build and index paths do not fetch.
- `src/source/languages.zig` and discovery route Java and Clojure source units.
- `src/frontend/tree_sitter.zig` is the only C ABI adapter.
- `src/frontends/{java,clojure}.zig` translate parse trees into frontend
  batches.
- `src/core/contract.zig`, `src/core/reconcile.zig`, and `src/core/graph.zig`
  already preserve facts, unresolved designators, external targets, dependency
  declarations, identity correspondence, stale assertions, and published
  snapshots.
- `src/main.zig` is a developer-only inspection command and not a public
  contract.

Semantic Code Indexing is required by repository policy when available. If
callable semidx MCP tools are unavailable in the implementation environment,
record that fallback in the progress log and use targeted direct inspection.

## Plan-Level Decisions

**Zig coverage starts with dogfood value, not completeness.** A fresh agent
should be able to inspect semidx's own top-level declarations and simple
same-file call edges. Anything requiring Zig namespace, import, comptime, field,
or method semantics stays unsupported or unresolved until a separate plan.

**Tree-sitter node assumptions must be tested before extraction grows.** The
first Zig frontend stage should include focused fixtures that expose the exact
node shapes used for declarations and simple calls. If the selected grammar
does not expose a construct cleanly, reduce coverage instead of guessing.

**Same-unit call resolution is exact only under the narrow rule.** A call like
`foo(...)` may become a `CALLS` fact only when `foo` uniquely names a covered
current Zig function definition in the same source unit and the syntax is not a
builtin, field access, namespace access, method call, or imported symbol.

**MCP is graph-first and source-text-off by default.** Tool results return
semantic context and ranges. Source text requires an explicit server startup
flag and bounded output tests.

**MCP compatibility is stdio-first.** Implement the local stdio server before
any HTTP transport. Support both the `2025-06-18` initialize lifecycle and the
`2026-07-28` stateless discovery path if they can share one small dispatcher.
If they cannot, stop and record the selected compatibility target before
shipping the server.

## Architecture Boundaries

1. `source/languages` and `source/discovery`
Responsibility: recognize `.zig` files and create source units.
Does not know about: Zig syntax, graph facts, or MCP.

2. `frontend/tree_sitter`
Responsibility: load the Zig parser through the existing C ABI boundary.
Does not know about: semantic kinds, source discovery, MCP, or graph storage.

3. `frontends/zig`
Responsibility: translate covered Zig parse nodes into frontend batches with
Zig extension vocabulary, core `definition` entities, and narrow same-unit
`CALLS`/`REFERENCES` facts or unresolved designators.
Does not know about: filesystem scanning, graph allocation, public protocols,
or cross-unit repository lookup.

4. `frontends/root` and `Index`
Responsibility: route Zig units to the Zig frontend and publish consistent
snapshots after scans, edits, and refreshes.
Does not know about: MCP JSON-RPC details.

5. `mcp`
Responsibility: speak MCP over stdio and map tool calls to snapshot queries.
Does not know about: parser internals or identity correspondence rules.

6. `tests` and `fixtures`
Responsibility: make parser availability, Zig coverage, incremental freshness,
MCP protocol behavior, output bounds, and no-source-text defaults observable.

## Stages

### Stage 1: Zig Grammar And Language Registration

Purpose: route `.zig` source units through a local parser dependency while
preserving parser-free core builds.

Likely files:

- `build.zig`
- `scripts/setup-tree-sitter-grammars.sh`
- `src/source/languages.zig`
- `src/frontend/tree_sitter.zig`
- `src/frontends/root.zig`
- new `src/frontends/zig.zig`
- focused tests in `src/source/`, `src/frontend/`, or `src/frontends/`

Required behavior:

- Add `.zig` discovery as `model.Language.zig` or the repository's equivalent
  language enum value.
- Add `tree-sitter-zig` as a local grammar source with an exact pinned commit.
  Use <https://github.com/tree-sitter-grammars/tree-sitter-zig> unless
  implementation-time inspection finds a licensing, maintenance, or generated-C
  blocker.
- Compile the Zig parser in the full lane only.
- Keep `zig build test-core -Dgrammars-dir=/nonexistent --summary all` green.
- Add a skeletal Zig frontend that can parse a unit and report
  `analysis_failed`, `analysis_unavailable`, or confirmed empty coverage
  without emitting invented facts.

Done when:

- `.zig` files are discovered in scans.
- Full tests can parse a minimal Zig fixture when grammar sources exist.
- Parser-free core tests still pass without grammar sources.
- Unsupported or empty Zig input is observable and not misreported as a fact.

### Stage 2: Zig Definition Facts

Purpose: make a useful repository map for Zig source without modeling the whole
language.

Likely files:

- `src/frontends/zig.zig`
- `src/frontends/root.zig`
- `src/core/model.zig` only if a new language enum or extension tag is needed
- `fixtures/vertical-slice/zig/*.zig`
- `tests/vertical_slice_test.zig`

Required behavior:

- Emit source-unit `file` entities through existing source ingestion.
- Emit current `definition` facts for covered named top-level Zig declarations:
  top-level functions and exact top-level type/container declarations where the
  selected grammar exposes the declared name unambiguously.
- Attach Zig extension vocabulary such as `zig.construct=function` or
  `zig.construct=container` without widening the shared core.
- Emit `DEFINES` from the file/source unit to each covered definition.
- Use the existing identity-evidence pattern. Do not derive stable identity
  from tree-sitter node ids or ranges.
- Treat local variables, fields, anonymous tests, imported bindings, builtins,
  comptime blocks, methods inside containers, and unclear grammar cases as
  unsupported or uncovered.

Done when:

- A fixture with multiple top-level declarations produces stable current
  definitions and `DEFINES` facts.
- A function body edit preserves definition identity.
- A definition rename remains identity loss under the current rules.
- Unsupported Zig constructs do not become approximate assertions.

### Stage 3: Zig Same-Unit Simple Calls

Purpose: add the first useful Zig relationship without crossing into imports or
namespace resolution.

Likely files:

- `src/frontends/zig.zig`
- `fixtures/vertical-slice/zig/edits/*.zig`
- `tests/vertical_slice_test.zig`
- optionally `fixtures/repository-scale/zig/`

Required behavior:

- For `foo(...)` inside a covered Zig function body, emit a same-unit `CALLS`
  fact when exactly one current covered top-level Zig function definition named
  `foo` exists in that source unit.
- Preserve the existing specialization rule: calls answer reference queries
  without double-counting the same occurrence.
- Leave `@builtin(...)`, `x.foo(...)`, `ns.foo(...)`, imported names, missing
  names, ambiguous local candidates, and unsupported call shapes unresolved or
  uncovered.
- Do not add cross-unit Zig dependencies in this plan.

Done when:

- Same-unit simple calls in a Zig fixture are facts with current freshness,
  source ranges, and Zig producer provenance.
- A callee body edit preserves identities and leaves callers current unless
  existing invalidation rules require reanalysis.
- A callee rename causes the previous call to become unresolved or identity
  loss under existing graph behavior, not a silent retarget.
- Java and Clojure behavior stays unchanged.

### Stage 4: Local MCP Stdio Preview

Purpose: expose graph-backed answers to local AI clients so the project becomes
useful as a development tool before persistence or public contracts exist.

Likely files:

- new `src/mcp/root.zig`
- new `src/mcp/stdio.zig`
- new `src/mcp/protocol.zig`
- new `src/mcp/tools.zig`
- new `src/mcp/main.zig`
- `build.zig`
- `tests/mcp_smoke_test.zig` or an equivalent integration test
- `docs/mcp/local_preview.md`

Required behavior:

- Add an executable such as `semidx-mcp`.
- Add a build/run step that can start the server for a configured root, for
  example `zig build mcp -- --root .`.
- On startup, scan the configured root into an in-memory graph and publish one
  snapshot before answering graph tools.
- Implement stdio framing: one UTF-8 JSON-RPC message per line; stdout contains
  only MCP messages; diagnostics/logs go to stderr.
- Implement MCP capability negotiation/discovery:
  - `initialize` and `notifications/initialized` for `2025-06-18` clients;
  - `server/discover` for `2026-07-28` clients if it can share the dispatcher;
  - `tools/list`; and
  - `tools/call`.
- Provide these initial tools:
  - `semidx_health`: reports root, snapshot revision, unit counts, graph counts,
    language coverage, parser availability, and diagnostic counts.
  - `semidx_repo_map`: returns files and top-level definitions with bounded
    output and optional language/path filters.
  - `semidx_find_definitions`: finds definitions by name, path, language, kind,
    freshness, and resolution.
  - `semidx_references`: returns `REFERENCES`/`CALLS` touching a named or
    identified entity, preserving specialized-call behavior.
  - `semidx_context`: returns a bounded graph neighborhood around an entity,
    path, or name: definitions, incoming/outgoing relationships, diagnostics,
    ranges, producers, resolution, freshness, and snapshot revision.
  - `semidx_refresh`: rescans the configured root and publishes the next
    consistent snapshot.
- Return `structuredContent` when the negotiated MCP version supports it, plus
  a compact text fallback for clients that only consume text blocks.
- Enforce source-text-off by default. With no opt-in flag, no tool result may
  embed source text; results may include repository-relative paths and ranges.
- Bound every list result with a limit/default and a truncation marker. Do not
  add pagination unless the implementation keeps it small and tested.

Done when:

- A smoke test starts `semidx-mcp`, sends initialization/discovery,
  `tools/list`, and one or more `tools/call` requests, then verifies valid
  JSON-RPC responses.
- The smoke test fails if stdout contains non-protocol logs.
- Tool results include resolution, freshness, producer, diagnostics, and
  snapshot revision.
- A no-source-text test proves default tool output does not include fixture
  source bodies.
- `semidx_refresh` observes an edited or added `.zig` fixture through a new
  snapshot without mixing old and new graph state in one response.

### Stage 5: Dogfood, Documentation, And Handoff

Purpose: make the feature usable and leave precise evidence for review.

Likely files:

- `docs/mcp/local_preview.md`
- `README.md`
- `SPEC.md`
- `MEMORY.md`
- `docs/reports/004_zig_frontend_and_mcp_preview_progress.md`

Required behavior:

- Document that MCP is experimental and local-only.
- Document how to install grammar prerequisites, build `semidx-mcp`, start it
  for this repository, and configure a local MCP client.
- Document the default no-source-text behavior and the explicit opt-in flag.
- Update `SPEC.md` and `MEMORY.md` only for behavior that actually exists after
  implementation.
- Record exact verification commands, skipped checks, residual risks, and review
  handoff in the progress log.

Done when:

- A fresh local agent can start the MCP server and use it to find Zig
  definitions in `src/`.
- The progress log records commit hashes per stage and final review status.
- Completed plans/reports are not left looking like active work queues after
  final review.

## Verification Matrix

Run focused checks first, then the full lane:

- `zig build test-core -Dgrammars-dir=/nonexistent --summary all`
- `zig build test-core --summary all`
- `zig build test --summary all`
- `zig fmt --check build.zig src tests`
- `zig build run -- src`
- MCP smoke command or build step added by Stage 4
- `./scripts/check-agent-attribution.sh --all`
- `./scripts/check-memory-freshness.sh`
- `git diff --check`

Additional negative checks:

- Temporarily disable `.zig` discovery and confirm Zig fixture tests fail.
- Temporarily disable same-unit Zig call resolution and confirm call tests fail.
- Temporarily write a log line to MCP stdout and confirm the smoke test fails.
- Run MCP smoke with source-text opt-in disabled and confirm no source body text
  appears in tool results.

## Stop Conditions

- If no acceptable `tree-sitter-zig` source provides generated C parser files
  compatible with the current build boundary and license expectations, stop
  before implementation and record an ADR or plan revision selecting a parser
  source.
- If the grammar does not expose a construct with exact name evidence, remove
  that construct from initial coverage instead of approximating it.
- If a client compatibility target forces source text to be returned by default,
  stop. That conflicts with the default local-data boundary in ADR 005.
- If supporting both MCP protocol shapes makes the first server materially
  larger or ambiguous, stop Stage 4 after implementing one documented target and
  record the deferred compatibility work.
- If MCP tool output starts requiring a published semantic contract version,
  stop and settle `SPEC.md` public contract requirements first.

## Execution Recommendations

Recorded on 2026-09-14 at the maintainer's request. These are advice for how
to run the plan, not scope: they change no stage, DoD, or stop condition.

**Start from a fresh session.** Everything a new agent needs from earlier work
is in the commits, `MEMORY.md`, and the plan 003 report, and `RULES.md` makes it
read them. Before exploring code, check whether the semidx MCP server connects;
it timed out in the plan 003 session, and if it is unavailable again, record the
fallback in the progress log as this plan already requires.

**Split execution into two sessions at the Stage 3 / Stage 4 boundary.**

1. Session A runs Stages 1–3, the Zig frontend. It stays inside the existing
   ingestion pipeline: grammar, language registration, `frontends/zig.zig`, and
   fixtures. It ends with per-stage commits and an up-to-date progress log.
2. Between the sessions, review Stages 1–3 separately, as was done for plan 003.
3. Session B runs Stages 4–5, the MCP preview and documentation. `src/mcp/`
   depends only on published snapshots, so Session B needs the progress log, not
   Session A's context.

**Executor model.**

- Stages 1–4: Claude Opus 5. The main risks are the ones a model can miss without
  noticing: assuming tree-sitter-zig node shapes instead of testing them,
  letting a name match become a fact, breaking stdio framing with any stdout
  output, and applying the stop conditions, which call for judgment.
- Stage 5 alone is documentation and could run on Claude Sonnet 5. When it is
  the tail of Session B, switching models for it is not worth it.
- Other models were not assessed for this plan.

**Environment traps to clear before starting.**

- Stage 1 needs network access once: `./scripts/setup-tree-sitter-grammars.sh`
  fetches `tree-sitter-zig`. Approve that before Session A, or it stops at its
  first stage. Build and index steps stay offline.
- The MCP `2026-07-28` specification is newer than the May 2026 training cutoff
  of the recommended models. Session B must read the specification from the link
  in Sources Of Truth rather than implement `server/discover` from memory. If it
  cannot, take the stop condition for one protocol target and implement
  `2025-06-18` only.

## Review Focus

- Graph authority: MCP must not establish or relabel assertions.
- Resolution honesty: unsupported Zig constructs must not become facts or
  approximate relationships.
- Identity: Zig definitions must use source identity evidence, not parser node
  identity or ranges.
- Incrementality: refresh must publish complete snapshots and never mix partial
  update state into one response.
- Local operation: no build/index network access; no source-text MCP transfer
  without explicit opt-in.
- Compatibility: stdio framing, initialization/discovery, `tools/list`, and
  `tools/call` should match the documented MCP target.
