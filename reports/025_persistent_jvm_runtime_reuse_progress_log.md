---
title: "Persistent JVM Runtime Reuse Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-08-27"
---

# Persistent JVM Runtime Reuse Progress Log

Execution log for
[`plans/021_persistent_jvm_runtime_reuse_plan.md`](../plans/021_persistent_jvm_runtime_reuse_plan.md).

## Stage 0: Launch Path And First Profile

Status: completed on 2026-08-27.

Summary:

- Confirmed the process-model gap: existing server paths are long-lived once
  started, while `clojure -M:runtime` remains a one-shot CLI.
- Selected `runtime-http` as the first reuse profile.
- Deferred MCP HTTP reuse to a later stage because MCP HTTP adds session
  handling that is unnecessary for the first CLI-style request path.

Evidence:

- `src/semidx/runtime/cli.clj` starts the JVM, handles one request, and exits.
- `src/semidx/runtime/http.clj` starts an HTTP server and blocks.
- `src/semidx/mcp/server.clj` runs a stdio request loop for the process
  lifetime.
- `src/semidx/mcp/http_server.clj` runs a local HTTP MCP server.

## Stage 1: Pure Launcher Decision Kernel

Status: completed on 2026-08-27.

Summary:

- Added `semidx.runtime.launcher` as the pure decision kernel for local runtime
  reuse.
- Added normalization for profiles, desired runtime identity, and persisted
  runtime state.
- Added pure reuse decisions for:
  - missing state;
  - healthy runtime reuse;
  - root mismatch;
  - health-confirmed root mismatch;
  - health-confirmed repo-key mismatch;
  - profile mismatch;
  - endpoint mismatch;
  - dead PID;
  - closed port;
  - failed health check;
  - start lock contention.
- No process spawning, HTTP calls, daemon lifecycle, or runtime protocol changes
  were added in this stage.

Changed files:

- `src/semidx/runtime/launcher.clj`
- `test/semidx/runtime/launcher_test.clj`
- `plans/021_persistent_jvm_runtime_reuse_plan.md`
- `reports/025_persistent_jvm_runtime_reuse_progress_log.md`
- `FEATURES.md`
- `MEMORY.md`
- `docs/code-context.md`

Verification:

- `clojure -M:test -n semidx.runtime.launcher-test` passed: 3 tests, 34
  assertions, 0 failures, 0 errors.
- `clojure -M:test` passed: 314 tests, 2089 assertions, 0 failures, 0
  errors.
- `clojure -M:ccc check --root .` passed after refreshing changed code-context
  artifacts with `clojure -M:ccc refresh --root . --changed`.

## Next Stage

Stage 2 should add the runnable `runtime-http` request reuse slice:

- command entrypoint or alias for `status`, `start`, `stop`, and `request`;
- health-check and start-if-needed orchestration around the pure kernel;
- request forwarding to existing runtime HTTP endpoints;
- narrow smoke test proving two sequential requests reuse one runtime process.
