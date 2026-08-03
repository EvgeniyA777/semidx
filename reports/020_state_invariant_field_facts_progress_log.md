---
title: "State Invariant Field Facts Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-08-02"
---

# State Invariant Field Facts Progress Log

Tracks execution of `plans/017_state_invariant_field_facts_plan.md`.

## Stage 0 - Plan And ADR

- Status: completed.
- Summary: Authored `ADR-045` (fields modeled as relation target keys via two
  additive relation types, Java reference lane) and `plans/017` with a
  three-stage sequence (declares-field relations -> field-aware assembler ->
  writes-field relations). Established that both `plans/016` and `plans/013` were
  already complete, so the deferred field-level work is a new tranche gated by
  the now-delivered ADR-034 / plans/013 Stage 3 substrate, not a reopened stage.
- Changed files:
  - `adr/045-represent-entity-field-and-field-write-facts-as-typed-relations.md`
  - `plans/017_state_invariant_field_facts_plan.md`
  - `reports/020_state_invariant_field_facts_progress_log.md`
- Verification: documentation only; no code changed in this step.
- Known blockers: none.

## Stage 1 - declares-field Relations For The Java Lane

- Status: completed.
- Summary:
  - Registered `structure/declares-field` in `relations/relation-types`.
  - Added a conservative Java-lane field producer in `languages/java.clj`
    (`java-field-relations` plus helpers). It emits `structure/declares-field`
    relations only for class-body field declarations of entity-like classes
    (entity annotation on the class, an entity/model path segment, or an
    entity/model class or module suffix). Method-body locals are excluded via
    method line-span filtering. Annotations (including multi-line JPA
    annotations) and best-effort nullability ride in `evidence_location`.
  - Wired relations into both the regex (`parse-java-regex`) and tree-sitter
    (`parse-java-tree-sitter`) result maps, so field extraction is
    engine-agnostic; the lane emitted no relations before this stage.
  - Each relation uses source `path::module` (a synthetic class node, not a
    unit) and target key `pkg.Class#field`. Because a field has no unit,
    relations normalize to `unresolved` and are ignored by resolved-only
    traversal, so callers/callees, `impact_analysis`, and `relation_support`
    stay byte-identical. The assembler is untouched (packet stays `1.0`).
- Changed files:
  - `src/semidx/runtime/relations.clj`
  - `src/semidx/runtime/languages/java.clj`
  - `test/semidx/integration/runtime_test.clj`
  - `MEMORY.md`
  - `reports/020_state_invariant_field_facts_progress_log.md`
- Verification:
  - REPL compile/load probes for `languages.java` and `relations`, plus a
    functional probe over a JPA-style entity: 5 fields extracted, method-body
    local excluded, nullability parsed from `@Column(nullable = false)` / `@Id`,
    non-entity class emits nothing, all relations `unresolved`,
    resolved-only traversal from the class node returns no edges, and
    `relation_diagnostics` empty.
  - `clojure -M:test -n semidx.integration.runtime-test -n
    semidx.runtime.state-invariants-test -n semidx.runtime.relations-test`:
    passed, 132 tests / 603 assertions.
  - `clojure -M:test`: passed, 288 tests / 1937 assertions.
  - `./scripts/run-mvp-gates.sh`: `mvp_gates=ok`; contracts, 21/21 benchmarks,
    four query smokes.
  - `./scripts/run-semantic-quality-report.sh`: unchanged pre-existing
    non-gating advisory baseline (`gate_eligible=false`, 5/6 expected-change,
    identity 1.0, move/rename 1.0). No regression from this stage.
- Known limitations:
  - `./scripts/validate-language-onboarding.sh java` fails with 12 errors, all
    pre-existing and unrelated to this diff: the validator expects the pre-split
    scaffold (`parse-java` in `adapters.clj`) and onboarding artifacts
    (`test/semidx/integration/java_onboarding_test.clj`,
    `fixtures/retrieval/java-*.json`, `docs/language-onboarding/java.md`) that
    the legacy Java lane never had (Java predates the ADR-022 onboarding flow;
    `plans/013` Stage 1 moved lane logic into `languages/java.clj`). This diff
    touches only `java.clj`, `relations.clj`, and the integration test, none of
    which the failing patterns reference.
- Known blockers: none.
