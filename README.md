# semidx

**Local semantic code graph for coding agents: exact when it knows, honest when
it does not.**

semidx builds an incrementally maintained semantic graph of a local codebase. It
records source entities, program relationships, resolution, freshness,
provenance, identity, and diagnostics so search tools, MCP clients, IDEs, and AI
coding agents can ask better questions before reading piles of files.

Think of it as local semantic code indexing for AI agent code search and impact
analysis, with provenance attached to every answer that matters.

The graph is the product. Text search, vector embeddings, RAG, MCP, editor
features, and impact analysis are consumers of the graph, not substitutes for
it. If semidx reports a relationship as a fact, that relationship was
established by source ingestion, a language frontend, or exact graph resolution.
If it cannot prove something, it keeps the answer unresolved, unsupported,
stale, unavailable, or approximate instead of dressing a guess as knowledge.

## What It Helps With

semidx is aimed at developers who use coding agents on real repositories and
want local, bounded, source-aware context:

- map files and top-level definitions before broad manual exploration;
- find where a named definition is introduced;
- inspect calls, references, and nearby graph context around a target;
- distinguish facts from unresolved designators and unsupported constructs;
- refresh after edits so an agent stops relying on stale context;
- keep source text out of MCP results by default.

The first promise is not complete language understanding. The first promise is
honest semantic context that is local, queryable, and explicit about its limits.

## Current Preview

**Status: first vertical slice, `0.1.0-preview.2`.** The repository contains a
small in-memory graph implementation over Java, Clojure, and Zig source under
`src/`, `tests/`, and `fixtures/`, plus an experimental local MCP stdio preview
called `semidx-mcp`.

Implemented today:

- parser-free shared core for entities, assertions, facts, unresolved targets,
  stale state, diagnostics, identity evidence, dependency invalidation, and
  published snapshots;
- repository-scale source ingestion with source-unit identity across edits and
  exact single-file moves;
- narrow Java, Clojure, and Zig frontends with declared fixture-scoped coverage;
- Java same-package top-level type facts under a deliberately narrow rule;
- Zig top-level functions and containers, direct member functions, same-unit
  bare calls, and exact local relative `@import` alias calls;
- local MCP tools: `semidx_health`, `semidx_outline`, `semidx_repo_map`,
  `semidx_find_definitions`, `semidx_references`, `semidx_context`, and
  `semidx_refresh`, with response budgets and snapshot-bound continuation.

Not present yet:

- persistence, file watching, daemon lifecycle, HTTP/gRPC, subscriptions, package-manager distribution, or binary releases;
- a published semantic contract version or stable public schema set;
- complete Java, Clojure, or Zig language support;
- vectors, embeddings, a retrieval pipeline, or source-text output by default.

See the [preview capability matrix](docs/spec/capability_matrix.md) for the
exact current coverage and known false negatives.

## Quick Start

semidx targets [Zig](https://ziglang.org) **0.16.0 exactly**.

The parser-free shared core can be checked without grammar setup:

```sh
./scripts/check-zig-version.sh
zig build test-core
```

The full preview also needs pinned tree-sitter grammar sources and a local
tree-sitter runtime that provides `tree_sitter/api.h` and `libtree-sitter.a`.
The setup script fetches the pinned grammars once; builds and index runs do not
fetch from the network.

```sh
./scripts/setup-tree-sitter-grammars.sh
zig build test
zig build run -- fixtures/vertical-slice/java/Greeter.java
```

`zig build` reports missing prerequisites and the flags that point at custom
locations, including `-Dgrammars-dir=` and `-Dtree-sitter-prefix=`.

## Use It From An MCP Client

Build the preview server:

```sh
./scripts/setup-tree-sitter-grammars.sh
./scripts/check-zig-version.sh
zig build
zig-out/bin/semidx-mcp --version
```

Register the stable launcher with your MCP client using absolute paths:

```json
{
  "mcpServers": {
    "semidx": {
      "type": "stdio",
      "command": "/path/to/semidx/scripts/semidx-mcp.sh",
      "args": ["--root", "/path/to/your/repository"]
    }
  }
}
```

`--root` names the local repository you want the agent to inspect. It does not
have to be the semidx checkout. One built semidx binary can serve many local
repositories by registering one MCP server per root.

For a first agent session, use this habit loop:

1. `semidx_health` to check the root, snapshot revision, languages, parsers,
   diagnostics, and whether the graph is current enough.
2. `semidx_outline` to see which directories and files hold units,
   definitions, and diagnostics, without listing every definition.
3. `semidx_repo_map` with a `path_prefix` to orient by files and top-level
   definitions in the part that matters.
4. `semidx_find_definitions` before opening likely definition files.
5. `semidx_references` or `semidx_context` before editing a target.
6. `semidx_refresh` after edits, before trusting later graph answers.

By default MCP results contain graph values only: paths, ranges, entity names,
ids, relationships, resolution, freshness, producers, and diagnostics. semidx
itself opens no network connection and returns no source text unless the server
is started with the explicit `--allow-evidence-text` opt-in. A hosted MCP client
may still send tool results to its service; semidx cannot control what the
client does after receiving them.

The full MCP reference is in [docs/mcp/local_preview.md](docs/mcp/local_preview.md).

## How semidx Thinks

The architectural center is deliberately small:

- **nodes are entities, not chunks**;
- **facts, unresolved assertions, and approximate assertions stay distinct**;
- **semantic identity should survive edits when correspondence is established**;
- **the graph is incrementally maintained and published as consistent
  snapshots**;
- **language frontends preserve language meaning instead of flattening it for a
  consumer**;
- **local operation is required**.

That identity is frozen in
[ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md), ratified on
2026-09-13. The rationale is in
[ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md). Changing requirements
live in [SPEC.md](SPEC.md), shared-core candidates live in [CORE.md](CORE.md),
and verification scenario families live in [CONFORMANCE.md](CONFORMANCE.md).

## For Agents

If you are an AI agent reading this repository, start with:

- [RULES.md](RULES.md) for repository instructions and source-of-truth routing;
- [MEMORY.md](MEMORY.md) for current implementation reality, known gaps, and
  near-term priorities;
- [docs/mcp/local_preview.md](docs/mcp/local_preview.md) for MCP tool behavior;
- [docs/spec/capability_matrix.md](docs/spec/capability_matrix.md) before
  making language-support claims;
- [docs/design/001_project_roadmap.md](docs/design/001_project_roadmap.md) for
  current direction.

Do not infer unsupported semantic relationships from names, grep hits, or
unresolved designators. semidx's useful difference is not that it knows
everything; it is that it says how each answer was produced and how far that
answer was resolved.

## Documentation Map

| Document | Use it for |
| --- | --- |
| [ARCHITECTURE_CONSTITUTION.md](ARCHITECTURE_CONSTITUTION.md) | Frozen product identity and architectural constraints |
| [ARCHITECTURE_RATIONALE.md](ARCHITECTURE_RATIONALE.md) | Why those constraints exist |
| [SPEC.md](SPEC.md) | Changing requirements and semantic contract lifecycle |
| [CORE.md](CORE.md) | Shared-core roster candidates and admission evidence |
| [CONFORMANCE.md](CONFORMANCE.md) | Verification scenario families |
| [MEMORY.md](MEMORY.md) | Current reality, gaps, risks, and priorities |
| [docs/mcp/local_preview.md](docs/mcp/local_preview.md) | Building and using the local MCP preview |
| [docs/spec/capability_matrix.md](docs/spec/capability_matrix.md) | Current preview coverage and limitations |

## License

Apache License 2.0. See [LICENSE](LICENSE).
