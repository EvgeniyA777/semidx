---
title: "Agent Graph Intelligence Layer"
doc_type: "idea"
lifecycle: "concept"
status: "draft"
agent_action: "use_as_input_for_future_plan_only"
updated: "2026-07-13"
---

# Idea: Agent Graph Intelligence Layer

Source: research follow-up from `ideas/010_repository_graph_tools_research.md`.
Status: concept

## Summary

Build a semidx graph intelligence layer that turns the existing semantic index into staged architecture views, PR impact maps, graph lint checks, dead-code candidates, docs/ADR-linked context, handoff state, and agent-ready MCP tools.

The larger product direction is for semidx to evolve from code search into an agent workflow substrate: a trustworthy context layer with fresh indexes, impact reasoning, repo rules, documentation context, session handoff state, and explicit behavior guardrails for AI coding agents.

The core principle is deterministic graph data first. LLMs should be optional and used only for labels, summaries, diagram narration, or repair suggestions, not as the source of truth for code relationships.

## Ideas To Adapt

### 1. Two-Stage Architecture Graph Generation

GitDiagram uses a two-stage pipeline: first create a concise architecture explanation from the repo tree and README, then turn that explanation plus the file tree into a structured graph, validate paths, and render the result.

For semidx:

- Generate an `architecture_graph` projection from the semantic index.
- Use deterministic nodes and edges from indexed facts.
- Optionally ask an LLM for short labels, grouping names, and human-facing summaries.
- Validate every non-null path against the indexed file list.
- Export Mermaid, DOT, JSON, and possibly static HTML.

### 2. One-Command Or URL-Like Entry Point

GitDiagram and gitcgr both win on onboarding by making graph generation a one-step action.

For semidx:

- Add a local command such as `clojure -M:runtime graph --root . --out graph.html`.
- Add MCP tools such as `export_graph`, `get_architecture_graph`, or `get_dependency_path`.
- Keep the first result useful without requiring users to tune many options.

### 3. Staged Drill-Down Instead Of Full Graph Dump

CodeSee starts from collapsed folders and lets users hide or focus parts of the map. Orbis demonstrates that full 3D graphs become noisy on large repositories.

For semidx:

- Do not render the entire symbol graph by default.
- Use staged views: repository -> module/community -> symbol -> callers/callees.
- Add focus mode around one selected file, module, or symbol.
- Add visibility filters for tests, fixtures, generated files, external dependencies, and low-confidence edges.
- Prefer 2D, inspectable diagrams over 3D as the default.

### 4. Explicit Typed Graph Schema

Code-Graph-RAG exposes a detailed graph schema with typed nodes and relationships.

For semidx:

- Make graph node and edge types explicit and documented.
- Candidate edge types:
  - `CONTAINS`
  - `DEFINES`
  - `CALLS`
  - `REFERENCES`
  - `IMPORTS`
  - `EXPORTS`
  - `IMPLEMENTS`
  - `INHERITS`
  - `TESTS`
  - `CONFIGURES`
  - `CO_CHANGES_WITH`
  - `ROUTE_HANDLES`
  - `DEPENDS_ON_EXTERNAL`
- Include confidence and provenance fields for edges that come from heuristics.

### 5. Content-Hash Freshness And Incremental Indexing

Codebase-Memory uses content hashes and file watching to keep a persistent graph fresh. This aligns with the existing Stage 0+1 workspace freshness plan.

For semidx:

- Prioritize `workspace_state`, `freshness`, and `index_lifecycle`.
- Reuse an index only when the workspace fingerprint matches.
- Surface lifecycle fields in MCP/HTTP/gRPC/library responses.
- Never allow a stale graph to be reported as a cache hit.
- Make freshness an agent-facing trust signal: fresh, stale, rebuilding, reused, or degraded.
- Include files changed since the selected snapshot when available.
- Lower confidence or require re-indexing when an answer depends on stale graph data.

### 6. Docs, Rules, And ADRs As First-Class Context

Repowise combines graph data with generated docs, decisions, git intelligence, and MCP tools. This addresses a real semidx gap: the index knows code structure, but not always why decisions were made.

For semidx:

- Index selected non-code files such as `RULES.md`, `AGENTS.md`, `CLAUDE.md`, `README.md`, ADRs, plans, and docs.
- Link decisions and documentation to code nodes when paths or symbols are mentioned.
- Track staleness for docs that reference changed code.
- Surface relevant rules and decisions in `resolve_context` and `impact_analysis` results.
- Surface repo rules as context so agents do not skip MCP, use tools before a task exists, silently fall back to manual exploration, or fabricate explanations under uncertainty.
- Keep behavior rules distinct from architecture facts: rules govern how agents act; graph facts describe code and documentation relationships.

### 7. Impact Analysis As A Pre-Change Gate

`impact_analysis` should become a standard planning step before multi-file changes, shared-class edits, public API changes, or retrieval-policy changes.

For semidx:

- Return a plan-oriented blast-radius summary: affected callers, dependents, related tests, risky neighbors, confidence, and freshness state.
- If impact is unexpectedly broad or confidence is low, instruct the agent to stop and ask before editing.
- Include a compact "why these files matter" explanation so the agent can reason about the change instead of treating impact as a file list.
- Preserve the simple MCP shape where an agent can call `impact_analysis` with only `index_id` plus a plain-language `intent`.

### 8. PR-Oriented Impact Maps

CodeSee review maps and Repowise change-risk features point toward a diff-oriented graph view.

For semidx:

- Combine `snapshot_diff` and `impact_analysis` into a `review_context` or `change_map` surface.
- Return changed units, affected callers, related tests, risky neighbors, and missing co-changes.
- Make the output suitable for PR review, agent planning, and commit handoff.

### 9. CI-Friendly Graph Linting

Madge and dependency-cruiser are useful because they produce actionable build-time signals: cycles, orphans, leaves, forbidden dependencies, DOT/SVG/JSON exports, and rule violations.

For semidx:

- Add an `architecture_lint` surface.
- Candidate checks:
  - dependency cycles
  - forbidden layer crossings
  - orphan modules
  - unexpectedly central hubs
  - test-to-production dependency inversions
  - generated or vendored code leaking into architecture views
- Support machine-readable output and optional CI failure modes.

### 10. Dead-Code Candidates

Code-Graph-RAG detects dead code by walking from roots over `CALLS` and `REFERENCES` edges.

For semidx:

- Add `dead_code_candidates`.
- Treat results as review candidates, not safe deletions.
- Let callers configure roots:
  - public API
  - CLI entrypoints
  - tests
  - routes
  - background jobs
  - framework lifecycle hooks
  - reflection/dynamic dispatch escape hatches

### 11. Agent Handoff Without A Manual `progress.txt`

The broader direction is to replace fragile manual progress notes with computed operational state.

For semidx:

- Add `handoff_summary` from `snapshot_diff`, git log, dirty files, failing checks, and selected unresolved notes.
- Include rejected decisions and active blockers when those are available from docs or agent session artifacts.
- Keep this separate from static rules: rules say how agents work; handoff says where the repo currently stands.
- Treat `semidx + git log + frequent commits` as covering most of what a manual progress file provides.
- Explicitly report gaps that semidx cannot infer: rejected designs, uncommitted intent, known-but-unencoded bugs, environment failures, and active blockers.
- Prefer computed evidence over agent memory, and mark inferred handoff items as inferred.

## Things Not To Copy

- Do not make a full 3D graph the core experience. It is visually appealing but likely poor as the default for large repositories.
- Do not use LLM-generated graph edges as source of truth. Use LLMs for labeling and summarization only.
- Do not require a heavyweight external graph database for the default path. Keep semidx usable with the current in-memory and PostgreSQL directions; graph DB export can be optional.
- Do not turn visualization into a standalone screenshot feature. The graph should feed decisions, agent tools, review, and planning.

## Possible MVP Sequence

1. Implement trustworthy freshness: `workspace_state`, `freshness`, `index_lifecycle`, and lifecycle diagnostics.
2. Export deterministic graph JSON and DOT from the existing index.
3. Add `architecture_graph` projection with coarse nodes and confidence/provenance.
4. Make `impact_analysis` a pre-change planning surface with freshness and blast-radius signals.
5. Add `change_map` by combining `snapshot_diff` and `impact_analysis`.
6. Add graph lint checks for cycles, orphan modules, and forbidden layer crossings.
7. Add docs/rules/ADR indexing and decision-to-code links.
8. Add optional Mermaid/static HTML rendering.
9. Add dead-code candidate detection.
10. Add computed `handoff_summary`.

## Sources

- GitDiagram: https://github.com/ahmedkhaleel2004/gitdiagram
- GitDiagram app: https://gitdiagram.com/
- gitcgr: https://gitcgr.com/
- Code-Graph-RAG: https://github.com/vitali87/code-graph-rag
- Codebase-Memory paper: https://arxiv.org/abs/2603.27277
- Repowise: https://github.com/repowise-dev/repowise
- CodeSee docs: https://docs.codesee.io/docs/getting-started
- Orbis: https://dev.to/nilofer_tweets/orbis-turn-any-github-repository-into-an-interactive-3d-dependency-graph-3eei
- Madge: https://github.com/pahen/madge
- Dependency Cruiser: https://github.com/sverweij/dependency-cruiser
