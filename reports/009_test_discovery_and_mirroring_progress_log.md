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
- [ ] **Step 2 (Mirror test namespaces to src)**: Not started
- [ ] **Step 3 (Record convention in RULES.md)**: Not started

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
- **Status**: Not started

### Step 3 — Record convention in RULES.md
- **Status**: Not started

## Notes

- Entry command `clojure -M:test` must stay stable: it is called by
  `scripts/run-mvp-gates.sh`, `scripts/validate-language-onboarding.sh`, and
  `scripts/new-language-adapter.sh`.
- Baseline before this work: 208 tests, 1513 assertions, 0 failures (from the
  language-lane registry dedup, commit `a0a1c32`).
