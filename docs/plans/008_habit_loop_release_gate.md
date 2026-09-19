---
title: "Habit loop release gate"
doc_type: "plan"
lifecycle: "completed"
status: "completed"
agent_action: "historical_reference_only"
updated: "2026-09-17"
---

# 008: Habit Loop Release Gate

## Goal

Turn the semidx agent habit loop into a repeatable release gate that proves the
preview is useful on a real repository before broader promotion.

This plan packages the product proof around what early users care about:
connect locally, get bounded graph-backed orientation, inspect exact and
unresolved claims, edit locally, refresh, and keep source-data boundaries clear.

## Start Rule

Start this plan only after Plans 006 and 007 are completed or explicitly
superseded. This plan gates the product behavior after the semantic dogfood
coverage and MCP response-budget work have settled.

## Scope

- Define an executable or scripted release gate around the agent habit loop.
- Make the gate collect latency, output-size, diagnostics, freshness, and
  source-data-boundary evidence.
- Run the gate against a temporary copy of this repository and at least one
  small fixture/root profile.
- Produce release-candidate evidence that distinguishes hard gates from
  observations.
- Update docs so a future release can cite the gate without implying a stable
  semantic contract.

## Non-Scope

Do not cut a Git tag, publish binaries, add package-manager distribution, add
CI release automation, publish a semantic contract version, add persistence,
add HTTP, or require a remote service. This plan creates a gate and evidence;
it does not perform a release unless the user separately asks for one.

Do not use test count, line count, language count, or broad benchmark claims as
success metrics by themselves.

## Sources Of Truth

- [ARCHITECTURE_CONSTITUTION.md](../../ARCHITECTURE_CONSTITUTION.md), especially
  local operation, consistent observation, graph authority, and consumer
  independence.
- [Product adoption strategy](../design/002_product_adoption_strategy.md),
  especially first public proofs and success metrics.
- [CONFORMANCE.md](../../CONFORMANCE.md), for scenario families the gate may
  cite as partial evidence.
- [SPEC.md](../../SPEC.md), for contract lifecycle and optional outbound data.
- [Local MCP preview](../mcp/local_preview.md), for current operation and data
  boundaries.
- [Plan 005](005_mcp_preview_release_readiness.md), for the first preview
  release readiness lane.
- [Plan 006](006_zig_dogfood_semantic_coverage.md), for post-preview Zig
  dogfood semantics.
- [Plan 007](007_mcp_response_budget_and_schema_ergonomics.md), for response
  budget expectations.

## Current Evidence

The current `zig build dogfood` already exercises health, repository map,
definition lookup, references, context, edit, refresh, and recovery behavior on
a temporary copy of this repository. It also records timing and transcript sizes
as observations. This plan promotes that proof into a named release gate with
clear pass/fail criteria, multiple profiles, and release-candidate output.

## Plan-Level Decisions

**The habit loop is the product gate.** The project should not ask new users to
care until the local agent workflow is reproducibly useful.

**Metrics are evidence, not marketing.** Latency and output-size numbers may be
recorded and trended. They become hard gates only where the project can keep
them stable across local machines and repository growth.

**The gate stays local and offline after setup.** It must not require network
access, external services, hosted clients, or source-data transmission.

**Release gates cite current behavior only.** The gate must report
`semantic_contract_version: null` until the requirements lifecycle publishes a
contract.

**Profiles prevent one golden path.** Run at least a repository-copy profile and
a small fixture profile so the gate sees both realistic source and fast
diagnostic scenarios.

## Architecture Boundaries

1. Gate runner or build step
Responsibility: orchestrate local proof profiles, collect metrics, and fail
with actionable messages.
Does not know about: frontend grammar internals or semantic model details
outside tool results.

2. MCP stdio client tests
Responsibility: drive protocol calls, enforce timeouts, capture transcripts,
and validate result shapes.
Does not know about: how graph facts are produced.

3. Product docs
Responsibility: explain how to run the gate and what evidence it proves.
Does not know about: implementation-private test helpers.

4. Progress/release evidence
Responsibility: record exact commands, environment, pass/fail status,
observations, and residual risks.

## Stages

### Stage 1: Gate Specification

Purpose: make pass/fail behavior explicit before adding more machinery.

Likely files:

- `docs/reports/008_habit_loop_release_gate_progress.md`
- `docs/mcp/local_preview.md`
- optionally a new gate reference under `docs/mcp/` if the local preview
  reference becomes too long

Required behavior:

- Define the required call sequence:
  `semidx_health`, compact `semidx_repo_map`, `semidx_find_definitions`,
  `semidx_references`, `semidx_context`, file edit in a temporary root,
  `semidx_refresh`, and post-refresh lookup/context.
- Define required assertions: product version present, semantic contract null,
  parser availability visible, diagnostics visible, no source text by default,
  truncation metadata present, refresh revision changes after an edit, and
  later calls observe the new snapshot.
- Separate hard gates from recorded observations.

Done when:

- A fresh agent can read the specification and know what fails the gate.

### Stage 2: Gate Runner

Purpose: provide one command that runs the habit loop proof.

Likely files:

- `build.zig`
- `tests/mcp_dogfood_test.zig`
- `tests/mcp_stdio_client.zig`
- optional script under `scripts/` if a build step is not the right shape

Required behavior:

- Add or refine a command such as `zig build preview-gate` or make
  `zig build dogfood` explicitly serve as the release gate.
- Run the repository-copy profile without editing the real repository.
- Keep response and exit timeouts; kill child processes on timeout.
- Emit a concise evidence summary: profile, root type, source-unit count,
  timings, transcript sizes, diagnostics, refresh outcome, and source-text
  boundary checks.

Done when:

- The gate passes locally and fails clearly if any required call is missing,
  malformed, stale, unbounded, or leaks source text by default.

### Stage 3: Multi-Profile Coverage

Purpose: avoid overfitting the gate to one repository snapshot.

Likely files:

- `tests/mcp_dogfood_test.zig`
- `fixtures/`
- `docs/reports/008_habit_loop_release_gate_progress.md`

Required behavior:

- Add a small fixture/root profile with known unsupported, unresolved, and
  confirmed/current cases.
- Keep the repository-copy profile as the realistic product proof.
- Ensure both profiles run offline and consume the full stdout/stderr streams.

Done when:

- The gate proves both realistic dogfood utility and honest degradation on a
  small controlled root.

### Stage 4: Release-Candidate Evidence Packaging

Purpose: make the gate's output useful for future release decisions.

Likely files:

- `docs/reports/008_habit_loop_release_gate_progress.md`
- `docs/mcp/local_preview.md`
- `README.md` if it points users at preview proof commands
- `MEMORY.md`

Required behavior:

- Record exact commands and environment assumptions.
- Record hard pass/fail results separately from observed timings and sizes.
- Record skipped checks, if any, with reasons.
- State residual risks: unsupported languages, no stable semantic contract,
  no persistence, no HTTP, local-only operation, and hosted-client onward
  transmission outside semidx control.

Done when:

- A release manager can cite the gate evidence without re-reading the test
  source.

### Stage 5: Gate Review And Handoff

Purpose: make the gate maintainable after this plan.

Likely files:

- `docs/reports/008_habit_loop_release_gate_progress.md`
- `MEMORY.md`

Required behavior:

- Review whether the gate duplicates Plan 005 dogfood work or replaces it.
- Remove or mark historical any stale release-gate instructions that conflict
  with the new gate.
- Document how future plans should add a new profile or assertion without
  turning the gate into a broad benchmark suite.

Done when:

- The repository has one canonical local preview habit-loop gate.
- The progress log records review outcome, residual risk, and next recommended
  release action.

## Verification Strategy

Run:

- `./scripts/check-zig-version.sh`
- `zig build test-mcp`
- `zig build dogfood`
- the new or refined habit-loop gate command
- `zig build test` if shared test helpers or build steps change outside MCP

Gate assertions must inspect structured MCP results, not just stdout text, and
must check child process exit status and stderr/stdout stream discipline.

## Definition Of Done

- One documented command proves the local agent habit loop end to end.
- The gate runs without network access after local prerequisites are installed.
- Source text remains absent by default and evidence-text opt-in remains
  explicit.
- Metrics are recorded with clear hard-gate versus observation labels.
- Release-candidate docs state exactly what the gate proves and what it does
  not prove.
