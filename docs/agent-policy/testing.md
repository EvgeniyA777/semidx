---
title: "Testing and Verification Policy"
doc_type: "policy"
lifecycle: "active"
status: "active"
agent_action: "reference_for_context"
updated: "2026-09-14"
---

# Testing and Verification Policy

## Risk-Based Selection

Before implementing or executing a non-trivial staged plan, record a compact
risk matrix in the plan, progress log, or handoff:

| Requirement / guarantee | Failure risk | Lowest sufficient level | Boundary proof | Negative or bypass case | Evidence |
| --- | --- | --- | --- | --- | --- |
| Source document or code contract | What could fail | Unit / integration / contract / fixture / runtime smoke | Boundary uniquely proved here | Invalid, stale, unavailable, forbidden, divergent, or fallback case | Named test or command |

Choose the lowest level that reliably proves the behavior:

- Use plain unit tests for pure parsers, normalizers, policies, ranking helpers,
  identity functions, aggregation, and deterministic value transformations.
- Use focused integration tests when behavior depends on multiple runtime
  modules, provider orchestration, storage, generated classes, language adapters,
  or cross-module contracts.
- Use contract validation for JSON Schema artifacts, example payloads, MCP tool
  schemas, HTTP/gRPC boundaries, and public response shapes.
- Use fixture/golden tests for language lanes, provider-authority identity,
  source normalization, stale-artifact behavior, and semantic-quality
  regressions.
- Use runtime smoke checks for CLI, MCP stdio/HTTP, gRPC launchers, optional
  external service paths (database or otherwise), external toolchains, and
  process-runner behavior.

Do not test mechanical delegation merely to increase counts. Do test custom
branching, identity stability, merge/arbitration decisions, fallback behavior,
error translation, stale or unavailable inputs, and regressions for observed
defects.

## Mandatory Considerations

- Each changed public contract: valid payload, invalid payload, omitted optional
  fields, unknown fields or enum values where applicable, and compatibility with
  committed examples.
- Each provider or language-lane change: provider unavailable, unsupported
  language, stale source identity, external tool failure, empty result, malformed
  artifact, and fallback/degradation behavior.
- Each identity or arbitration change: same-key merge, must-not-merge fixture,
  provider-neutral key stability, authority precedence, freshness validation,
  and deterministic ordering.
- Each retrieval or ranking change: compact selection shape, expansion/detail
  continuity, token-budget behavior, impact hints, diagnostics, and low
  confidence handling.
- Each storage or service-edge change: in-memory path, the chosen persistence
  backend's path when touched, serialization boundaries, lifecycle cleanup, and
  error reporting.
- Each external runtime dependency: local absence, CI/offline behavior, path or
  env-var resolution, generated-artifact freshness, and startup mode.

## Verification Lanes

Use the narrowest meaningful command first, then the required regression lane.
Common lanes include:

| Lane | Command | Purpose |
| --- | --- | --- |
| Shared core | `zig build test-core` | The model, graph, and reconciliation with no parser dependency. The cheapest probe, and the only lane that runs without the tree-sitter prerequisites. |
| Full test lane | `zig build test` | Core plus the tree-sitter adapter, the language frontends, and the fixture and edit-history tests. |
| Formatting | `zig fmt --check build.zig src tests` | Instant, and it catches a broken edit before a compile does. |
| Runtime smoke | `zig build run -- <source files>` | Indexing and querying end to end with no service and no network. Its output is developer-only and nothing asserts against it. |
| MCP preview | `zig build test-mcp` | The MCP preview's unit tests and a stdio smoke test that runs `semidx-mcp` as a subprocess and fails on any non-protocol stdout, trailing stdout, or non-zero exit. Also part of `zig build test`. |
| Contract validation | No command. There is no public contract and no `contracts/` directory. | Record one here when a contract is published. |
| Release gates | No command. Nothing is released. | Record one here when release tooling exists. |

Run the narrowest lane that can fail on the change: `zig build test-core` for
shared-core edits, `zig build test` before any commit that touches a frontend,
the adapter, the build, or a fixture.

A runtime smoke passes only after the process exits with status 0 and the full
stdout/stderr streams have been consumed. Inspecting only an initial prefix,
summary, or progress line is not verification. When the command is meant to
produce text or protocol output, record whether the complete output contained
non-printable bytes, non-protocol stdout, or a late crash after a successful
summary.

Coverage reports are diagnostic. An arbitrary percentage does not replace
requirement and risk analysis.

## Local Services

- No local service dependency (database or otherwise) exists, and the first
  slice requires none: the tests run with nothing else present. When one is
  chosen, record it here with how tests should detect and reuse a running
  instance instead of restarting it needlessly.
- The build-time prerequisites are not services but local files: pinned
  tree-sitter grammar sources from `./scripts/setup-tree-sitter-grammars.sh`, and
  a tree-sitter runtime providing `tree_sitter/api.h` and `libtree-sitter.a`. A
  missing one fails `zig build` with a message naming the fix; it never degrades
  a lane silently. See
  [ADR 002](../adr/002_local_tree_sitter_parser_dependency.md).
- Before running integration tests that depend on a local service, check whether
  an instance is already running.
- If a local service must be restarted for a test, stop the existing instance
  cleanly, start a fresh one with the required test configuration, and run tests
  only after the clean restart.

## Isolation And Evidence

- Keep tests order-independent. They must not rely on run order or on shared
  mutable state between test units.
- Isolate data, clocks, ports, sessions, files, generated artifacts, and external
  state.
- Prefer deterministic fixtures and explicit cleanup.
- Do not hide nondeterminism with retries in a required gate. Record flakiness
  as a defect; quarantine only with owner, expiry, and visible status.
- Record the exact command, pass/fail result, test counts when available, and
  any environmental limitation.
- If a verification command cannot be run, report it explicitly and explain the
  remaining risk.
