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

## Stage 1 Closure - Adapter Facade Boundary

- Status: completed.
- Summary: Stage 1 is closed. `semidx.runtime.adapters` is now a thin public dispatch facade over per-language lane namespaces plus shared language helpers, and the remaining adapter-private TypeScript compatibility block has been removed instead of carried forward.
- Decision record: `ADR-035 Split Language Lanes Out Of The Adapter Facade`.
- Completed stage commits:
  - `bc9117f refactor: extract shared language helpers`.
  - `7d3f4ae refactor: move clojure lane out of adapters`.
  - `06201dd refactor: move java lane out of adapters`.
  - `12c2605 refactor: move python lane out of adapters`.
  - `0b4d630 refactor: move lua lane out of adapters`.
  - `29188ef refactor: remove typescript legacy adapter block`.
- Verification baseline at closure:
  - Compile probes passed for touched parser namespaces during each sub-stage.
  - Focused language/runtime suites passed during each sub-stage.
  - Latest full gate set passed: `clojure -M:test` (`230 tests / 1614 assertions`), `./scripts/run-benchmarks.sh` (`21/21` fixtures), `./scripts/run-semantic-quality-report.sh` (`advisory_failure` with unchanged baseline metrics), `./scripts/run-mvp-gates.sh` (`mvp_gates=ok`), and `clojure -M:ccc check --root .`.
- Next stage: Stage 2 - remove the hard runtime dependency on an externally installed tree-sitter CLI.
- Skipped / limitations: external reviewer loop was not run inside this documentation-only closure commit; implementation sub-stage verification is recorded above.
- Known blockers: none.

## Stage 2.1 - Tree-Sitter Toolchain Strategy ADR

- Status: completed.
- Scope: Decide and record the Stage 2 strategy for removing the hard runtime dependency on an externally installed `tree-sitter` CLI, and repair stale ADR placeholder references in `plans/013`.
- Decision record: `ADR-036 Use A Repo-Managed Tree-Sitter Toolchain`.
- Summary:
  - Regex parsing remains the guaranteed default.
  - Tree-sitter remains an optional accelerated parser path.
  - Runtime acceleration must resolve through explicit parser options, environment configuration, and a repository-managed toolchain provisioned by the grammar bootstrap path, with ambient `PATH` only as a developer fallback.
  - `plans/013` now references real accepted ADRs for Stage 1 (`ADR-035`) and Stage 2 (`ADR-036`), points Stage 3 at the accepted relation-first fork (`ADR-034`) plus a future scoping ADR, and avoids reusing occupied ADR numbers for later stages.
- Changed files:
  - `adr/036-use-a-repo-managed-tree-sitter-toolchain.md`
  - `plans/013_open_gaps_closure_program.md`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - semidx MCP mapping completed for shared tree-sitter helpers and Clojure/Java/TypeScript lane callers.
  - `git diff --check` passed.
  - `clojure -M:ccc check --root .` passed.
- Skipped / limitations: runtime tests and gates are deferred to the implementation sub-step because this commit records the strategy and plan repair only.
- Known blockers: none.

## Stage 2.2 - Repo-Managed Tree-Sitter Toolchain Resolution

- Status: completed.
- Scope: Implement `ADR-036` in runtime helpers and bootstrap tooling without changing the default parser path.
- Summary:
  - Regex parsing remains the guaranteed default.
  - Tree-sitter acceleration now resolves the CLI through explicit parser options, environment configuration, the repo-managed `.tree-sitter-grammars/bin/tree-sitter` link, then ambient `PATH` as a developer fallback.
  - Language lanes pass parser opts through tree-sitter availability probes and CST calls, so explicit missing CLI paths degrade through the existing unavailable-acceleration diagnostics instead of silently using an unrelated global executable.
  - The grammar bootstrap script now verifies/provisions a managed CLI link and can emit `SEMIDX_TREE_SITTER_CLI_PATH` alongside pinned grammar env vars.
- Changed files:
  - `src/semidx/runtime/languages/shared.clj`
  - `src/semidx/runtime/languages/clojure.clj`
  - `src/semidx/runtime/languages/elixir.clj`
  - `src/semidx/runtime/languages/java.clj`
  - `src/semidx/runtime/languages/typescript.clj`
  - `test/semidx/integration/runtime_test.clj`
  - `scripts/setup-tree-sitter-grammars.sh`
  - `docs/runtime-api.md`
  - `MEMORY.md`
  - `docs/roadmap-status.md`
  - `reports/014_open_gaps_closure_program_progress_log.md`
- Verification:
  - `bash -n scripts/setup-tree-sitter-grammars.sh` passed.
  - Compile probe passed for `semidx.runtime.languages.shared`, `semidx.runtime.languages.clojure`, `semidx.runtime.languages.java`, `semidx.runtime.languages.typescript`, and `semidx.runtime.languages.elixir`.
  - `clojure -M:test -n semidx.integration.runtime-test` passed (`104 tests / 472 assertions`).
  - `clojure -M:test -n semidx.integration.typescript-onboarding-test` passed (`3 tests / 11 assertions`).
  - `clojure -M:test` passed (`231 tests / 1618 assertions`).
  - `./scripts/run-benchmarks.sh` passed (`21/21` fixtures).
  - `./scripts/run-semantic-quality-report.sh` exited `0` with the expected advisory gate state: `expected_change_match_rate=0.8333333333333334`, `identity_stability_rate=1.0`, `move_rename_recovery_rate=1.0`, `implementation_vs_meaning_accuracy=0.6666666666666666`, `unmatched_rate=0.0`.
  - `./scripts/run-mvp-gates.sh` passed (`237 tests / 1638 assertions`, `21/21` retrieval benchmarks, all query smokes, `mvp_gates=ok`).
  - `clojure -M:ccc check --root .` passed after refreshing `docs/code-context.md`.
  - `git diff --check` passed.
- Skipped / limitations: the bootstrap script syntax was verified locally, but the networked grammar clone/fetch path was not rerun during this sub-step.
- Known blockers: none.
