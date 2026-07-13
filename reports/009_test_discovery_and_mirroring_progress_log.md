---
title: "Test Discovery and Mirroring Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-07-13"
---

# Progress Log: Test Discovery and Mirroring

Companion progress log for [012_test_discovery_and_mirroring_plan.md](../plans/012_test_discovery_and_mirroring_plan.md).

## Status Summary

- [x] **Step 1 (Auto-discovery)**: Implemented
- [x] **Step 2 (Mirror test namespaces to src)**: Implemented
- [x] **Step 3 (Record convention in RULES.md)**: Implemented

## Details of Changes

### Step 1 — Auto-discovery
- **Status**: Implemented
- **Changes**: added `org.clojure/tools.namespace {:mvn/version "1.5.0"}` to the
  `:test` alias; rewrote `semidx.test-runner` to discover every `*-test`
  namespace under `test/` (via `ns-find/find-namespaces-in-dir`), require them,
  run `clojure.test`, and exit non-zero on failures. Removed both hand-maintained
  namespace lists. Entry point `-m semidx.test-runner` (`clojure -M:test`) is
  unchanged, so the three scripts that call it are unaffected.
- **Finding (footgun confirmed)**: the old manual list held 20 namespaces but
  `test/semidx/` has 22 files — `compression-test` and `project-context-test`
  were never run. Discovery now runs them; both pass. Coverage rose from
  208 tests / 1513 assertions to **214 tests / 1544 assertions** with no manual
  edit — exactly the drift this plan targets.
- **Order-independence guard**: ran the full suite in a shuffled namespace order
  (22 namespaces) → 214 tests, 0 failures, 0 errors. No cross-namespace ordering
  coupling.
- **Verification**:
  - `clojure -M:test` (discovery, sorted): 214 tests, 1544 assertions, 0 failures.
  - shuffled-order run: 214 tests, 1544 assertions, 0 failures.

### Step 2 — Mirror test namespaces to src
- **Status**: Implemented
- **Changes**: moved all 22 test files into a layout that mirrors the code they
  cover and renamed their namespaces accordingly:
  - `test/semidx/runtime/` (11): compression, evaluation, freshness,
    language_registry, project_context, repo_identity, storage, usage_metrics,
    workspace_state, grpc (was runtime_grpc), http (was runtime_http).
  - `test/semidx/mcp/` (2): server (was mcp_server), http_server
    (was mcp_http_server).
  - `test/semidx/integration/` (9): the five language onboarding suites,
    freshness_baseline, freshness_regression, policy_governance, and the broad
    runtime_test end-to-end suite.
- **Safe-rename check**: no code references the old test namespaces, and no test
  requires another test namespace, so discovery (Step 1) finds them wherever they
  live. `git mv` preserved history.
- **Verification**: `clojure -M:test` → 214 tests, 1544 assertions, 0 failures.

### Step 3 — Record convention in RULES.md
- **Status**: Implemented
- **Changes**: `Repository Shape` now states test namespaces mirror `src` paths
  (`semidx.runtime.X` → `test/semidx/runtime/X_test.clj`), with MCP under
  `test/semidx/mcp/` and cross-cutting/integration under `test/semidx/integration/`.
  `Testing And Verification` now states tests are auto-discovered (no manual
  registration) and must stay order-independent.

## Known Follow-ups

- **`scripts/new-language-adapter.sh` is now stale (Step 1 fallout).** It still
  tries to insert a new onboarding test namespace into the removed manual list in
  `test_runner.clj` (anchored on `semidx.runtime-http-test`). With auto-discovery
  this insertion is unnecessary and no longer matches the file; the scaffolding
  step should be updated to drop the list edit (a scaffolded `*-test` namespace is
  found automatically). Tracked here; not fixed in this plan.

## Notes

- Entry command `clojure -M:test` must stay stable: it is called by
  `scripts/run-mvp-gates.sh`, `scripts/validate-language-onboarding.sh`, and
  `scripts/new-language-adapter.sh`.
- Baseline before this work: 208 tests, 1513 assertions, 0 failures (from the
  language-lane registry dedup, commit `a0a1c32`).
