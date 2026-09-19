---
title: "MCP response budget and schema ergonomics"
doc_type: "plan"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-17"
---

# 007: MCP Response Budget And Schema Ergonomics

## Goal

Make the local MCP preview cheaper and safer for coding agents to use by
default. The preview should keep the same graph authority while reducing
oversized responses, clarifying truncation, and making tool schemas easier to
maintain and test.

The user value is adoption friction: an agent should choose semidx before broad
manual search because the first graph-backed answer is compact enough to fit in
working context and structured enough to trust.

## Start Rule

Start this plan only after Plan 006 is completed or explicitly superseded. Plan
006 may change what the MCP tools return for Zig graph facts; this plan then
budgets and shapes those results.

## Scope

- Add response-budget discipline to MCP tool output without byte-chopping valid
  JSON.
- Improve `semidx_repo_map` and `semidx_context` ergonomics for cold-start and
  focused-edit workflows.
- Centralize or generate MCP tool input schemas enough to reduce drift between
  validation, docs, and advertised schemas.
- Add regression tests for result bounds, truncation metadata, schema validity,
  and default no-source-text behavior.
- Update the local preview reference and dogfood proof to recommend the cheaper
  habit loop.

## Non-Scope

Do not publish stable semantic schemas, add pagination, add HTTP, add resources
or prompts, add embeddings or ranking, require an external service, or turn MCP
tool shapes into the semantic model.

Do not solve every large-output case with one global byte limit that can emit
invalid JSON or hide which result set was truncated. Budgets must be expressed
through item selection, detail levels, and explicit metadata.

Do not remove existing resolution, freshness, producer, diagnostics, or
truncation information from detailed modes.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  sections 1, 3, 5, 7, and 8.
- [SPEC.md](../../SPEC.md), for the distinction between experimental preview
  tool shapes and future public contracts.
- [Product adoption strategy](../design/002_product_adoption_strategy.md),
  especially compact schemas, predictable results, and the agent habit loop.
- [Local MCP preview](../mcp/local_preview.md), for current tool behavior.
- [Preview capability matrix](../spec/capability_matrix.md), for current MCP
  output limits and source-derived data boundaries.
- [Plan 005](005_mcp_preview_release_readiness.md), for release-readiness
  dogfood evidence and refresh recovery behavior.
- [Plan 006](006_zig_dogfood_semantic_coverage.md), for any expanded Zig facts
  this plan must keep bounded.

## Current Evidence

The current dogfood proof over this repository reports useful startup and query
latency, but `semidx_repo_map {"limit":1000}` produces roughly hundreds of
kilobytes of transcript for a 56-unit repository. MCP lists are individually
bounded and report totals, but responses as a whole are not budgeted. Tool input
schemas are hand-written JSON strings in `src/mcp/tools.zig`, and validation
logic is separate from the advertised schema.

That is acceptable for a first preview, but it is not the best default for an
agent trying to conserve context during cold start.

## Plan-Level Decisions

**Budget by structure, not by truncating bytes.** Each tool should decide which
items and details to include before rendering JSON, then report totals,
truncation, and budget metadata.

**Detail levels are a preview ergonomics feature, not a semantic contract.**
The MCP preview may add arguments such as `detail` or `include_*` while
continuing to report `semantic_contract_version: null`.

**The default path optimizes for orientation.** Default responses should answer
"where should I look next?" Compact output may omit expensive per-entity detail
when the same tool offers a focused way to fetch it.

**Detailed graph evidence stays available.** `semidx_find_definitions`,
`semidx_references`, and `semidx_context` must continue to expose per-claim
resolution, freshness, producer, evidence location, and diagnostics in detailed
or focused calls.

**Schema work is internal quality work.** A helper or typed schema builder is
allowed if it reduces drift now. Do not build a general schema framework.

## Architecture Boundaries

1. `src/mcp/tools.zig`
Responsibility: MCP tool definitions, argument validation, response rendering,
detail levels, and budget metadata.
Does not know about: frontend grammar rules or semantic fact creation.

2. `src/mcp/protocol.zig` and `src/mcp/root.zig`
Responsibility: JSON-RPC/MCP envelope, protocol eras, and tool dispatch.
Does not know about: which graph facts are important for compact orientation.

3. `core/Snapshot`
Responsibility: immutable graph view and query filters.
Does not know about: MCP output budgets or client context limits.

4. Tests and dogfood
Responsibility: prove that compact defaults remain useful, detailed modes keep
evidence, and output bounds are stable enough for agents.

## Stages

### Stage 1: Response Inventory And Budget Targets

Purpose: make current output costs visible before changing tool shapes.

Likely files:

- `tests/mcp_dogfood_test.zig`
- `tests/mcp_stdio_client.zig`
- `docs/reports/007_mcp_response_budget_and_schema_ergonomics_progress.md`

Required behavior:

- Record transcript byte counts for health, repo map, definition lookup,
  references, context, refresh, and evidence-text mode over this repository.
- Identify which fields dominate `repo_map` and `context` output.
- Define preview budget targets as gates or soft observations per tool. Hard
  gates should cover regressions the project can keep stable; observations
  should remain labeled as observations.

Done when:

- The progress log contains baseline output-size evidence and the plan's chosen
  hard versus observational thresholds.

### Stage 2: Tool Schema And Argument Validation Cleanup

Purpose: reduce schema drift before adding detail-level arguments.

Likely files:

- `src/mcp/tools.zig`
- `tests/mcp_smoke_test.zig`
- focused tests in `src/mcp/` if appropriate

Required behavior:

- Centralize shared enum schemas and argument validators for `freshness`,
  `resolution`, `language`, `direction`, counts, and detail levels.
- Keep advertised schemas valid JSON objects.
- Test that unknown arguments and wrong types fail with useful tool errors.
- Keep annotations accurate: read-only tools stay read-only; `semidx_refresh`
  remains non-destructive to files.

Done when:

- Every advertised schema parses in tests.
- Validation behavior matches the schema for the shared argument types.

### Stage 3: Compact Repository Map

Purpose: make cold-start orientation cheaper.

Likely files:

- `src/mcp/tools.zig`
- `tests/mcp_smoke_test.zig`
- `tests/mcp_dogfood_test.zig`
- `docs/mcp/local_preview.md`

Required behavior:

- Add a compact default or explicit `detail` mode for `semidx_repo_map`.
- Ensure the compact response still reports unit path, language, analysis state,
  diagnostic counts, top-level definition names/roles, totals, and truncation.
- Keep a detailed mode available for current richer entity fields.
- Add budget metadata naming the mode and limits used.

Done when:

- The default cold-start repo map over this repository is materially smaller
  than the current detailed map while still letting an agent choose a focused
  next call.
- A detailed call can recover the richer entity information.

### Stage 4: Focused Context Budgeting

Purpose: keep `semidx_context` useful as the default focused-edit tool without
flooding the client.

Likely files:

- `src/mcp/tools.zig`
- `tests/mcp_smoke_test.zig`
- `tests/mcp_dogfood_test.zig`
- `docs/mcp/local_preview.md`

Required behavior:

- Add detail or include controls for relationship evidence, diagnostics, and
  full entity fields where useful.
- Preserve per-claim resolution/freshness/producer in modes that include
  relationships.
- Report totals and truncation separately for incoming relationships, outgoing
  relationships, diagnostics, and focus entities.
- Keep no-source-text default intact.

Done when:

- A focused context call around a semidx source target remains bounded and
  actionable.
- Tests prove detailed mode still exposes evidence needed for review and impact
  analysis.

### Stage 5: Documentation And Habit Loop Update

Purpose: teach agents the cheaper path.

Likely files:

- `docs/mcp/local_preview.md`
- `docs/spec/capability_matrix.md`
- `README.md` if it currently names the older call pattern
- `MEMORY.md`
- `docs/reports/007_mcp_response_budget_and_schema_ergonomics_progress.md`

Required behavior:

- Update examples to prefer compact orientation followed by focused definition,
  reference, or context calls.
- Document every new preview argument and its default.
- State that tool schemas are still experimental and not a published semantic
  contract.
- Record final dogfood output-size observations and residual large-output risk.

Done when:

- A fresh agent can read the local preview reference and avoid the old
  large-output call pattern.
- The capability matrix accurately describes MCP output bounds.

## Verification Strategy

Run:

- `./scripts/check-zig-version.sh`
- `zig build test-mcp`
- `zig build dogfood`
- `zig build test` when shared MCP helpers or snapshot filters change

Add focused tests that check schema validity, invalid argument handling, compact
versus detailed output shape, truncation totals, and no source text by default.

## Definition Of Done

- MCP tool outputs are budgeted through explicit structure and metadata.
- `semidx_repo_map` is cheap enough for default cold-start use on this
  repository.
- `semidx_context` remains bounded and still offers detailed graph evidence.
- Tool schemas and validators are tested against each other.
- Documentation teaches the compact habit loop and preserves the local,
  no-source-text-by-default boundary.
