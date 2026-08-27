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

## Stage 2: Runtime HTTP Request Reuse Slice

Status: completed on 2026-08-27.

Summary:

- Added the runnable `runtime-http` reuse slice behind the new `:launcher`
  alias: `status`, `start`, `stop`, and `request`.
- Split the side-effecting roles named by the plan into their own namespaces so
  the pure kernel stays pure and every role is fakeable in tests:
  - `semidx.runtime.launcher-state`: per-slot state file, start lock, log file.
  - `semidx.runtime.launcher-http`: health client and request client.
  - `semidx.runtime.launcher-process`: command, liveness, start, stop.
  - `semidx.runtime.launcher-cli`: command orchestration over injectable roles.
- `request` forwards to `/v1/retrieval/resolve-context` then
  `/v1/retrieval/fetch-context-detail`, mirroring
  `semidx.core/resolve-context-detail`. No request or response body is reshaped.
- Start-if-needed re-observes health after acquiring the exclusive per-slot
  lock, so two concurrent clients cannot start two runtimes for one project.
- Added runtime adoption: a healthy runtime already listening on the requested
  endpoint is recorded with `owned false` instead of being duplicated, and
  `stop` refuses to terminate a runtime the launcher did not start.
- Extended the pure kernel additively: `runtime-slot-key` for slot addressing
  and an optional `owned` field in `normalize-runtime-state`.

Design decisions worth recording:

- Launcher state lives under `~/.cache/semidx/runtime/<workspace_key>-<profile>/`,
  outside the repository, with owner-only permissions on the directory and the
  state file. `SEMIDX_RUNTIME_LAUNCHER_HOME` overrides it for tests and
  sandboxes. This addresses plan risk 3 without adding ignored repo paths.
- Plan risk 1 (wrong-repository reuse) is handled by two independent
  mechanisms: state is scoped per workspace/profile slot, and every forwarded
  request carries `root_path` explicitly, which the runtime HTTP edge uses to
  key its project registry. `GET /health` does not report a root, so the kernel
  correctly treats root confirmation as unavailable rather than mismatched.
- API key material is passed as `x-api-key` on forwarded requests and as
  `SEMIDX_RUNTIME_API_KEY` to a launcher-started child. It is never written to
  state, reports, or logs.

Changed files:

- `src/semidx/runtime/launcher.clj`
- `src/semidx/runtime/launcher_state.clj`
- `src/semidx/runtime/launcher_http.clj`
- `src/semidx/runtime/launcher_process.clj`
- `src/semidx/runtime/launcher_cli.clj`
- `test/semidx/runtime/launcher_state_test.clj`
- `test/semidx/runtime/launcher_cli_test.clj`
- `deps.edn`
- `docs/runtime-api.md`
- `plans/021_persistent_jvm_runtime_reuse_plan.md`
- `reports/025_persistent_jvm_runtime_reuse_progress_log.md`
- `FEATURES.md`
- `MEMORY.md`

Verification:

- `clojure -M:test -n semidx.runtime.launcher-state-test` passed: 5 tests, 24
  assertions, 0 failures, 0 errors.
- `clojure -M:test -n semidx.runtime.launcher-cli-test` passed: 11 tests, 63
  assertions, 0 failures, 0 errors.
- `clojure -M:test` passed: 330 tests, 2176 assertions, 0 failures, 0 errors.
- Manual end-to-end smoke against a real spawned runtime JVM on port 8899, with
  `SEMIDX_RUNTIME_LAUNCHER_HOME` pointed at a scratch directory:
  - `status` on a cold slot: `running false`, no process started.
  - `request` #1: `decision started`, 12.9s wall (JVM start plus initial index).
  - `request` #2: `decision reused`, 1.4s wall, no second runtime JVM.
  - Baseline `clojure -M:runtime` for the same query: 11.4s wall.
  - `status` while running: `running true`, `reason healthy_runtime`.
  - `stop`: `decision stopped`, `forced false`; a second `stop` reported
    `decision noop`, `reason no_state`; no runtime process was left behind.
  - Output diff against the one-shot CLI for the same root and query: identical
    `raw_context` unit ids and identical top-level keys except the additive
    `project_context` that the runtime HTTP edge already returns.

Known limitations:

- The automated reuse smoke test (`sequential-requests-reuse-one-runtime-smoke-test`)
  fakes the process runner and boots the runtime HTTP server in-process, so it
  proves state, locking, health, and forwarding, but not real JVM spawning. Real
  spawning was verified manually as recorded above; a scripted process smoke is
  left to Stage 4 hardening.
- Two projects that both accept the default port `8787` will adopt one another's
  runtime rather than start a second one. This is safe because the runtime HTTP
  edge is multi-project and each request carries `root_path`, but it means
  `stop` from the non-owning project reports `not_launcher_owned` instead of
  stopping anything. Pass `--port` per project when independent runtimes are
  wanted.
- The `mcp-http` profile is accepted by the kernel and by the process alias map,
  but it is untested end to end and is owned by Stage 3.

## Next Stage

Stage 3 should add the MCP HTTP profile and its documentation:

- launcher support or documented configuration for MCP HTTP reuse;
- client config snippets pointing at the reused local MCP HTTP endpoint;
- keep MCP stdio documented as host-lifetime scoped.
