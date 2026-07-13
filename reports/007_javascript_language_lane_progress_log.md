---
title: "JavaScript Language Lane Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "not_started"
agent_action: "reference_for_context"
updated: "2026-07-13"
---

# Progress Log: JavaScript Language Lane

Companion progress log for [010_javascript_language_lane_plan.md](../plans/010_javascript_language_lane_plan.md).

Implementation extends the existing TypeScript lane (shared parser core) rather
than adding a new parser. See the plan's "Design Decision" section.

## Status Summary

- [ ] **Commit 1 (Detection, activation, provider metadata)**: Not started
- [ ] **Commit 2 (JavaScript lane wired to shared core)**: Not started
- [ ] **Commit 3 (Freshness & language-policy regression coverage)**: Not started
- [ ] **Commit 4 (Cross-language retrieval coverage)**: Not started
- [ ] **Commit 5 (Optional tree-sitter follow-up)**: Deferred

## Details of Changes

### Commit 1 — Detection, activation, and provider metadata
- **Status**: Not started
- **Planned**: `.js`/`.jsx`/`.mjs`/`.cjs` → `"javascript"` in `language-by-path`;
  add `"javascript"` to `supported-language-order`; add `javascript-native`
  provider-catalog entry and bump `provider-registry-version`.
- **Verification (planned)**: `clojure -M:test`.

### Commit 2 — JavaScript lane wired to the shared core
- **Status**: Not started
- **Planned**: add `src/semidx/runtime/languages/javascript.clj` (thin delegation
  returning `:language "javascript"`); add the `"javascript"` dispatch case in
  `adapters/parse-file`; extend `ts-test-path?` for JS test/spec extensions;
  register `test/semidx/javascript_onboarding_test.clj` in `test_runner.clj`.
- **Verification (planned)**: `./scripts/validate-language-onboarding.sh javascript`
  and `clojure -M:test`.

### Commit 3 — Freshness and language-policy regression coverage
- **Status**: Not started
- **Planned**: `create-index`/`update-index` tests for JS add/change/delete/reuse;
  language-policy tests ensuring excluded JS files never enter full or incremental
  indexes.
- **Verification (planned)**: `clojure -M:test`.

### Commit 4 — Cross-language retrieval coverage
- **Status**: Not started
- **Planned**: fixture with interlinked `.js`/`.ts` modules; assert
  `resolve_context`/`impact_analysis` connect a JS caller to its callee across the
  ESM import edge.
- **Verification (planned)**: targeted retrieval tests + `clojure -M:test`
  (+ `./scripts/validate-contracts.sh` only if a contract surface changes).

### Commit 5 — Optional tree-sitter follow-up
- **Status**: Deferred
- **Planned**: wire `SEMIDX_TREE_SITTER_JAVASCRIPT_GRAMMAR_PATH` and route the
  tree-sitter engine through the `javascript` grammar; keep regex core as default
  and fallback.
- **Verification (planned)**: `./scripts/validate-language-onboarding.sh javascript`
  and the full suite.

## Notes

- Pre-existing gap identified during planning: `ts-test-path?` matched only
  `.ts`/`.tsx`, so JavaScript test files routed through the shared core would be
  classified as `function` instead of `test`. Fixed as part of Commit 2.
- `package.json` manifest hint remains mapped to `"typescript"` for the first
  slice; JS-only detection relies on source files (tracked as a Medium risk in
  the plan).
