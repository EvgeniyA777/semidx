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

- [ ] **Step 1 (Auto-discovery)**: In progress
- [ ] **Step 2 (Mirror test namespaces to src)**: Not started
- [ ] **Step 3 (Record convention in RULES.md)**: Not started

## Details of Changes

### Step 1 — Auto-discovery
- **Status**: In progress
- **Planned**: add `org.clojure/tools.namespace` to the `:test` alias; rewrite
  `semidx.test-runner/-main` to discover every `*-test` namespace on the test
  paths, require them, run `clojure.test`, and exit non-zero on failures; remove
  the two hand-maintained namespace lists. Keep `-m semidx.test-runner` so
  `clojure -M:test` and the three scripts that call it are unchanged.
- **Guard**: verify the suite passes in a non-fixed namespace order.
- **Verification (planned)**: `clojure -M:test` discovers ≥ 208 tests / 1513
  assertions, green; the three scripts still pass.

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
