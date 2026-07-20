---
title: "Open Gaps Closure Program Progress Log"
doc_type: "progress_log"
lifecycle: "active"
status: "in_progress"
agent_action: "reference_for_context"
updated: "2026-07-20"
---

# Open Gaps Closure Program Progress Log

Tracks execution of `plans/013_open_gaps_closure_program.md`.

## Prerequisite Baseline Unblock

- Status: completed.
- Summary: Removed stale demonstration `constraints.snapshot_id` pins from runnable query examples so `scripts/run-mvp-gates.sh` can execute examples against the current worktree index without weakening runtime snapshot-bound validation.
- Commit: `cbb3782 test: unpin runnable query examples`.
- Verification:
  - `./scripts/validate-contracts.sh` passed (`checked_json_files=61`, `contracts_validation=ok`).
  - `./scripts/run-mvp-gates.sh` passed with local socket permissions (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, `mvp_gates=ok`).
- Notes: The non-escalated sandbox run failed with `java.net.SocketException: Operation not permitted` while binding local HTTP/MCP test sockets; the same gate passed when rerun with local socket permissions.

## Stage 1.1 - Shared Language Helpers

- Status: completed.
- Scope: Extract shared scanning, signature, token, unit-boundary, and tree-sitter CLI/config/CST helpers into `semidx.runtime.languages.shared` while preserving existing private helper names in callers through wrappers.
- Architecture plan:
  - Goal: reduce duplicated language-lane infrastructure without changing parser behavior.
  - Boundary: `semidx.runtime.languages.shared` owns generic line/token/tree-sitter helper mechanics; language lanes keep language-specific regexes, parsing policy, AST interpretation, and semantic-core logic.
  - Contract direction: lane modules depend on the shared helper namespace; shared helpers do not depend on lane modules.
  - Sequencing: keep adapters and extracted lanes on wrapper functions first, then move full Clojure/Java/Python/Lua lane bodies in later sub-steps.
- Changed files:
  - `src/semidx/runtime/languages/shared.clj`
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/typescript.clj`
  - `src/semidx/runtime/languages/elixir.clj`
  - `src/semidx/runtime/languages/elixir/shared.clj`
  - `src/semidx/runtime/languages/css.clj`
  - `src/semidx/runtime/languages/html.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for all touched namespaces.
  - Shared tree-sitter config path smoke passed for default and TypeScript-prefixed filenames.
  - `clojure -M:test -n semidx.integration.typescript-onboarding-test` passed (`3 tests / 11 assertions`).
  - `clojure -M:test -n semidx.integration.css-onboarding-test` passed (`2 tests / 16 assertions`).
  - `clojure -M:test -n semidx.integration.html-onboarding-test` passed (`2 tests / 16 assertions`).
  - `clojure -M:test` passed (`225 tests / 1590 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/validate-language-onboarding.sh typescript --skip-gates` passed structural checks.
  - `./scripts/validate-language-onboarding.sh html --skip-gates` passed structural checks.
  - `./scripts/validate-language-onboarding.sh css --skip-gates` passed structural checks.
  - `./scripts/run-mvp-gates.sh` passed with local socket permissions (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
  - `clojure -M:ccc check --root .` passed after refreshing CCC artifacts.
- Skipped / limitations:
  - `./scripts/validate-language-onboarding.sh elixir --skip-gates` failed because the validator expects legacy `elixir-happy-path.json` / `elixir-ambiguity.json` fixtures and old adapter-branch patterns; current Elixir coverage is through existing Elixir benchmark fixtures and full test gates.
- Known blockers: none.

## Stage 1.2 - Clojure Lane Extraction

- Status: completed.
- Scope: Move the Clojure parser lane out of `semidx.runtime.adapters` into `semidx.runtime.languages.clojure`, including regex fallback, clj-kondo primary parsing, optional tree-sitter extraction, Clojure call extraction, multimethod/protocol handling, and parser diagnostics.
- Architecture plan:
  - Goal: make `semidx.runtime.languages.clojure` the real Clojure lane owner instead of a wrapper around adapter internals.
  - Boundary: `adapters/parse-file` remains the cross-language dispatcher; Clojure-specific parsing internals live in the Clojure lane namespace.
  - Cleanup: removed the legacy public `adapters/parse-clojure-file` facade and updated tests to redefine `clj-language/parse-file` directly.
  - Shared helper follow-up: centralized `safe-line` implementation in `semidx.runtime.languages.shared` because current non-Clojure adapter paths, including TypeScript tree-sitter extraction, still use the same line-signature behavior.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/clojure.clj`
  - `src/semidx/runtime/languages/shared.clj`
  - `test/semidx/integration/runtime_test.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.languages.shared`, `semidx.runtime.languages.clojure`, and `semidx.runtime.adapters`.
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`225 tests / 1590 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
- Skipped / limitations: none.
- Known blockers: none.

## Stage 1.3 - Java Lane Extraction

- Status: completed.
- Scope: Move the Java parser lane out of `semidx.runtime.adapters` into `semidx.runtime.languages.java`, including Java regex parsing, optional tree-sitter extraction, overload/constructor unit identity, superclass metadata, static-import ownership, method references, and call arity indexing.
- Architecture plan:
  - Goal: make `semidx.runtime.languages.java` the real Java lane owner instead of a wrapper around adapter internals.
  - Boundary: `adapters/parse-file` remains the cross-language dispatcher; Java-specific regexes, call extraction, parser policy, and tree-sitter interpretation live in the Java lane namespace.
  - Cleanup: removed the legacy public `adapters/parse-java-file` facade and dispatches directly to `java-language/parse-file`.
  - Dependency cleanup: removed Java-only `edn`, `sh`, and `set` namespace requirements from `semidx.runtime.adapters` after the move.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/java.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.languages.java` and `semidx.runtime.adapters`.
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`225 tests / 1590 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
- Skipped / limitations: none.
- Known blockers: none.

## Stage 1.4 - Python Lane Extraction

- Status: completed.
- Scope: Move the Python parser lane out of `semidx.runtime.adapters` into `semidx.runtime.languages.python`, including Python module normalization, import and relative-import expansion, class/method ownership, self/class call expansion, local symbol collision handling, nested-scope suppression, and test-target module linkage.
- Architecture plan:
  - Goal: make `semidx.runtime.languages.python` the real Python lane owner instead of a wrapper around adapter internals.
  - Boundary: `adapters/parse-file` remains the cross-language dispatcher; Python-specific regexes, import state, call extraction, parser policy, and semantic ownership logic live in the Python lane namespace.
  - Cleanup: removed the legacy public `adapters/parse-python-file` facade and dispatches directly to `py-language/parse-file`.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/python.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.languages.python` and `semidx.runtime.adapters`.
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`225 tests / 1590 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`225 tests / 1590 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
- Skipped / limitations: none.
- Known blockers: none.

## Stage 1.5 - Lua Lane Extraction

- Status: completed.
- Scope: Move the Lua parser lane out of `semidx.runtime.adapters` into `semidx.runtime.languages.lua`, including Lua module normalization, `require` import tracking, table/function/method ownership, returned-module owner detection, local call suppression, and test-target module linkage.
- Architecture plan:
  - Goal: make `semidx.runtime.languages.lua` the real Lua lane owner instead of a wrapper around adapter internals.
  - Boundary: `adapters/parse-file` remains the cross-language dispatcher; Lua-specific regexes, import state, call extraction, parser policy, and module ownership logic live in the Lua lane namespace.
  - Cleanup: removed the legacy public `adapters/parse-lua-file` facade and dispatches directly to `lua-language/parse-file`.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `src/semidx/runtime/languages/lua.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.languages.lua` and `semidx.runtime.adapters`.
  - `clojure -M:test -n semidx.integration.lua-onboarding-test` passed (`2 tests / 7 assertions`).
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`230 tests / 1614 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`230 tests / 1614 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
  - `clojure -M:ccc check --root .` passed after refreshing CCC artifacts.
- Skipped / limitations: none.
- Known blockers: none.

## Stage 1.6 - TypeScript Legacy Adapter Cleanup

- Status: completed.
- Scope: Remove the remaining legacy TypeScript parser block from `semidx.runtime.adapters` after the TypeScript lane already owned the implementation, and route TypeScript/JavaScript dispatch directly to their language namespaces.
- Architecture plan:
  - Goal: keep adapters as a cross-language dispatcher only, without carrying duplicate TypeScript regex/tree-sitter parsing or compatibility fallbacks.
  - Boundary: `semidx.runtime.languages.typescript` owns TypeScript regex parsing, optional tree-sitter parsing, import/call expansion, object-literal/class-field/default-export/re-export extraction, and parser diagnostics; `semidx.runtime.languages.javascript` owns JavaScript parse dispatch and language tagging.
  - Cleanup: removed adapter-level TypeScript regexes, tree-sitter helpers, `parse-typescript-legacy`, `parse-typescript`, and the private `parse-javascript` wrapper.
- Changed files:
  - `src/semidx/runtime/adapters.clj`
  - `MEMORY.md`
- Verification:
  - Compile probe passed for `semidx.runtime.adapters`, `semidx.runtime.languages.typescript`, and `semidx.runtime.languages.javascript`.
  - `clojure -M:test -n semidx.integration.typescript-onboarding-test` passed (`3 tests / 11 assertions`).
  - `clojure -M:test -n semidx.integration.javascript-onboarding-test` passed (`4 tests / 34 assertions`).
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`103 tests / 468 assertions`).
  - `clojure -M:test` passed (`230 tests / 1614 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`230 tests / 1614 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
- Skipped / limitations: none.
- Known blockers: none.
